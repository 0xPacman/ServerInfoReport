"""Linux regression and real PTY tests; Python is needed only for development."""
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import signal
import struct
import subprocess
import tempfile
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "infoReport.sh"


def shell(source, *, env=None):
    result = subprocess.run(
        ["bash", "-c", f"source {shlex.quote(str(SCRIPT))}\n{source}"],
        text=True, capture_output=True, timeout=20, env=env,
    )
    if result.returncode:
        raise AssertionError(f"exit {result.returncode}: {result.stderr}\n{result.stdout}")
    return result.stdout


class Collectors(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.proc = self.root / "proc"
        self.sys = self.root / "sys"
        self.proc.mkdir()
        self.sys.mkdir()
        (self.proc / "loadavg").write_text("1.00 2.00 3.00 1/100 100\n")

    def tearDown(self):
        self.temp.cleanup()

    def run_fixture(self, body):
        return shell(f"PROC={shlex.quote(str(self.proc))}; SYS={shlex.quote(str(self.sys))}\n{body}")

    def test_cpu_excludes_guest_and_counts_iowait_separately(self):
        (self.proc / "stat").write_text("cpu 140 0 30 880 40 0 0 10 999 999\ncpu0 140 0 30 880 40 0 0 10 999 999\n")
        out = self.run_fixture('PREV_CPU[cpu]="1000 820 20"; collect_cpu; printf "%s %s %s" "$CPU_PCT" "$CPU_WAIT" "$LOAD"')
        self.assertEqual(out, "0 20 1.00 2.00 3.00")  # 100 elapsed, 100 idle + wait

    def test_cpu_real_delta_and_counter_reset(self):
        (self.proc / "stat").write_text("cpu 200 0 100 700 0 0 0 0 0 0\n")
        self.assertEqual(self.run_fixture('PREV_CPU[cpu]="900 640 0"; collect_cpu; printf %s "$CPU_PCT"'), "40")
        self.assertEqual(self.run_fixture('PREV_CPU[cpu]="1200 800 0"; collect_cpu; printf %s "$CPU_PCT"'), "null")

    def test_memory_fallback_and_no_swap(self):
        (self.proc / "meminfo").write_text("MemTotal: 1000 kB\nMemFree: 100 kB\nBuffers: 50 kB\nCached: 200 kB\nSReclaimable: 50 kB\nShmem: 20 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n")
        self.assertEqual(self.run_fixture('collect_memory; printf "%s %s %s" "$MEM_AVAILABLE" "$MEM_PCT" "$SWAP_PCT"'), "389120 62 null")

    def test_network_elapsed_time_and_counter_reset(self):
        (self.proc / "net").mkdir()
        (self.proc / "net/dev").write_text("eth0: 3000 0 2 3 0 0 0 0 6000 0 4 5 0 0 0 0\n")
        out = self.run_fixture('ELAPSED_MS=2000; PREV_NET[eth0]="1000 2000"; collect_network; printf %s "${NET_ROWS[0]}"')
        self.assertEqual(out, "eth0|unknown|1000|2000|3000|6000|6|8")
        out = self.run_fixture('ELAPSED_MS=2000; PREV_NET[eth0]="9000 9000"; collect_network; printf %s "${NET_ROWS[0]}"')
        self.assertIn("|null|null|", out)

    def test_disk_sectors_are_512_bytes_and_elapsed_is_measured(self):
        (self.sys / "block/sda").mkdir(parents=True)
        (self.proc / "diskstats").write_text("8 0 sda 0 0 200 0 0 0 300 0 2 1500 0\n")
        out = self.run_fixture('ELAPSED_MS=2000; PREV_IO[sda]="100 100 500"; collect_io; printf %s "${IO_ROWS[0]}"')
        self.assertEqual(out, "sda|25600|51200|50|2")

    def test_process_name_with_spaces_parentheses_and_pid_reuse(self):
        (self.proc / "42").mkdir()
        fields = ["0"] * 30
        fields[0], fields[11], fields[12], fields[19], fields[21] = "R", "150", "50", "100", "10"
        (self.proc / "42/stat").write_text("42 (worker ) pool) " + " ".join(fields) + "\n")
        body = 'ELAPSED_MS=1000; CLK_TCK=100; PAGE_SIZE=4096; PREV_PROCESS[42]="100 100"; collect_processes; printf %s "${PROCESS_ROWS[0]}"'
        self.assertEqual(self.run_fixture(body), "42|R|100|40960|worker ) pool")
        self.assertIn("|null|", self.run_fixture(body.replace('100 100"', '100 99"')))

    def test_filesystems_with_spaces_and_inode_data(self):
        out = shell('''
bounded() {
    if [[ $* == *"-i"* ]]; then
        printf 'Filesystem Inodes IUsed IFree IUse%% Mounted on\n/dev/test 1000 900 100 90%% /mnt/data disk\n'
    else
        printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/test 1000 700 300 70%% /mnt/data disk\n'
    fi
}
collect_filesystems; printf '%s' "${FS_ROWS[0]}"
''')
        self.assertEqual(out, "/dev/test|1024000|716800|307200|70|90|/mnt/data disk")

    def test_alerts_are_current_not_accumulated(self):
        out = shell('CPU_PCT=90; MEM_PCT=20; check_alerts; printf "%s:%s " "$STATUS" "${#ALERT_ROWS[@]}"; CPU_PCT=10; check_alerts; printf "%s:%s" "$STATUS" "${#ALERT_ROWS[@]}"')
        self.assertEqual(out, "1:1 0:0")

    def test_partial_df_failure_preserves_valid_mounts(self):
        out = self.run_fixture('''
bounded() {
    printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\n/dev/root 1000 700 300 70%% /\\n'
    return 1
}
collect_filesystems; printf '%s\\n' "${FS_ROWS[@]}"
''')
        self.assertIn("/dev/root|1024000|716800|307200|70|70|/", out)
        self.assertIn("Some filesystem/inode queries failed", out)

    def test_filesystem_arguments_skip_remote_mounts_and_decode_spaces(self):
        (self.proc / "mounts").write_text("/dev/root / ext4 rw 0 0\n/dev/data /mnt/data\\040disk xfs rw 0 0\nserver:/data /mnt/remote nfs4 rw 0 0\nproc /proc proc rw 0 0\n")
        self.run_fixture('''
bounded() {
    printf '%s\\n' "$@" >> "$PROC/calls"
    printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\n/dev/root 1000 500 500 50%% /\\n'
}
collect_filesystems
''')
        arguments = (self.proc / "calls").read_text().splitlines()
        self.assertIn("/mnt/data disk", arguments)
        self.assertNotIn("/mnt/remote", arguments)
        self.assertNotIn("-l", arguments)

    def test_json_escaping_round_trips_control_characters(self):
        raw = 'a"b\\c\n\t\r\x1b<&>'
        out = shell(f"json_quote {shlex.quote(raw)}")
        self.assertEqual(json.loads(out), raw)

    def test_unknown_metrics_are_json_null_and_values_are_numbers(self):
        data = json.loads(shell('HOST="test"; write_json'))
        self.assertIsNone(data["cpu"]["usage_percent"])
        self.assertIsNone(data["memory"]["swap_percent"])
        self.assertIsInstance(data["memory"]["total_bytes"], int)

    def test_terminal_control_characters_are_sanitized(self):
        self.assertEqual(shell("safe $'hello\\e[2J\\tworld'; printf %s \"$REPLY\""), "hello?[2J?world")

    def test_failed_export_preserves_existing_destination(self):
        dest = self.root / "report.json"
        dest.write_text("original")
        shell(f'''write_report() {{ printf partial; return 2; }}
export_report {shlex.quote(str(dest))} json && exit 9
exit 0''')
        self.assertEqual(dest.read_text(), "original")
        self.assertFalse(list(self.root.glob(".serverinfo.*")))

    def test_html_escapes_host_and_process_data(self):
        out = shell('HOST="<script>alert(1)</script>"; write_report html')
        self.assertNotIn("<script>", out)
        self.assertIn("&lt;script&gt;", out)


class Integration(unittest.TestCase):
    def run_script(self, *args):
        return subprocess.run(["bash", str(SCRIPT), *args], text=True, capture_output=True, timeout=45)

    def test_invalid_cli_inputs_fail_before_collection(self):
        for args in [("--interval",), ("--interval", "0"), ("--interval", "x"), ("--cpu-threshold", "101"), ("--format", "xml"), ("--services", "x;touch pwn"), ("--theme", "unknown"), ("--unknown",)]:
            with self.subTest(args=args):
                result = self.run_script(*args)
                self.assertEqual(result.returncode, 2)
                self.assertIn("infoReport:", result.stderr)

    def test_real_snapshot(self):
        result = self.run_script("--report", "--interval", "1", "--format", "json", "--no-alerts")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        data = json.loads(result.stdout)
        self.assertGreater(data["sample_ms"], 0)
        self.assertGreater(data["cpu"]["cores"], 0)
        self.assertGreater(data["memory"]["total_bytes"], 0)
        self.assertTrue(data["processes"])
        self.assertTrue(any(isinstance(fs["usage_percent"], int) for fs in data["filesystems"]))
        self.assertNotIn("\x1b", result.stdout)

    def test_watch_outputs_two_json_objects(self):
        result = self.run_script("--watch", "--count", "2", "--interval", "1", "--format", "json", "--no-alerts")
        self.assertEqual(result.returncode, 0, result.stderr)
        data = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual([d["sample"] for d in data], [1, 2])

    def test_atomic_export_private_mode(self):
        with tempfile.TemporaryDirectory() as temp:
            dest = Path(temp) / "report with spaces.json"
            result = self.run_script("--interval", "1", "--output", str(dest), "--format", "json", "--no-alerts")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(dest.read_text())["schema_version"], 1)
            self.assertEqual(dest.stat().st_mode & 0o777, 0o600)
            self.assertFalse(list(Path(temp).glob(".serverinfo.*")))

    def test_explicit_tui_rejects_a_pipe(self):
        result = self.run_script("--tui")
        self.assertEqual(result.returncode, 2)
        self.assertIn("interactive terminal", result.stderr)

    def test_minimal_path_without_optional_commands(self):
        with tempfile.TemporaryDirectory() as temp:
            for name in ("bash", "awk", "sort", "df", "date", "sleep", "uname"):
                os.symlink(shutil.which(name), Path(temp) / name)
            env = dict(os.environ, PATH=temp)
            result = subprocess.run(["bash", str(SCRIPT), "--report", "--interval", "1", "--format", "json", "--no-alerts"], env=env, capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads(result.stdout)
            self.assertGreater(data["memory"]["total_bytes"], 0)
            self.assertIsNone(data["filesystems"][0]["usage_percent"])
            self.assertTrue(any("timeout missing" in note for note in data["notes"]))

    def test_terminal_is_restored_after_sigterm(self):
        master, slave = pty.openpty()
        before = termios.tcgetattr(slave)
        env = dict(os.environ, TERM="xterm")
        proc = subprocess.Popen(["bash", str(SCRIPT), "--tui", "--interval", "60"], stdin=slave, stdout=slave, stderr=slave, env=env, start_new_session=True)
        output = bytearray()
        try:
            deadline = time.monotonic() + 15
            while b"\x1b[?1049h" not in output and time.monotonic() < deadline:
                if select.select([master], [], [], 0.2)[0]:
                    output.extend(os.read(master, 65536))
            self.assertIn(b"\x1b[?1049h", output)
            proc.send_signal(signal.SIGTERM)
            proc.wait(timeout=10)
            self.assertEqual(proc.returncode, 143)
            self.assertEqual(termios.tcgetattr(slave), before)
        finally:
            if proc.poll() is None:
                proc.kill(); proc.wait()
            os.close(master); os.close(slave)

    def test_interactive_navigation_resize_export_and_cleanup(self):
        with tempfile.TemporaryDirectory() as temp:
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 32, 120, 0, 0))
            before = termios.tcgetattr(slave)
            env = dict(os.environ, TERM="xterm-256color")
            proc = subprocess.Popen(["bash", str(SCRIPT), "--tui", "--interval", "1", "--no-alerts"], stdin=slave, stdout=slave, stderr=slave, cwd=temp, env=env, start_new_session=True)
            output = bytearray()

            def drain(seconds=0.2):
                deadline = time.monotonic() + seconds
                while time.monotonic() < deadline:
                    if select.select([master], [], [], 0.05)[0]:
                        output.extend(os.read(master, 65536))

            try:
                deadline = time.monotonic() + 35
                while b"sample 1" not in output and time.monotonic() < deadline:
                    drain()
                self.assertIn(b"sample 1", output)
                os.write(master, b" ")  # pause while navigating
                os.write(master, b"t"); drain()
                self.assertIn(b"theme: nord", output)
                for key in b"234567":
                    os.write(master, bytes([key])); drain()
                os.write(master, b"5/bash\r"); drain()
                self.assertIn(b"filter: bash", output)
                os.write(master, b"?"); drain()
                self.assertIn(b"KEYBOARD", output)
                os.write(master, b"?")
                fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 10, 40, 0, 0))
                os.kill(proc.pid, signal.SIGWINCH); drain()
                self.assertIn(b"resize to at least", output)
                fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
                os.kill(proc.pid, signal.SIGWINCH)
                os.write(master, b"e"); drain(1)
                exported = list(Path(temp).glob("serverinfo-*.json"))
                self.assertEqual(len(exported), 1)
                self.assertEqual(json.loads(exported[0].read_text())["schema_version"], 1)
                os.write(master, b"q")
                proc.wait(timeout=10); drain()
                self.assertEqual(proc.returncode, 0)
                self.assertIn(b"\x1b[?1049l", output)
                self.assertEqual(termios.tcgetattr(slave), before)
            finally:
                if proc.poll() is None:
                    proc.kill(); proc.wait()
                os.close(master); os.close(slave)


if __name__ == "__main__":
    unittest.main(verbosity=2)
