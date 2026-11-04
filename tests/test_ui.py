"""Exercise the actual Bash renderer at multiple terminal sizes, without a TTY."""
import os
import re
import unittest

def render_fixture(columns=120, rows=36, theme="midnight", ascii_mode=False, color=True, page=0):
    from test_monitor import shell

    fixture = f"""
ROWS={rows}; COLS={columns}; THEME={theme}; ASCII={int(ascii_mode)}; COLOR={int(color)}; PAGE={page}
UI_LOCALE=C.UTF-8
terminal_size() {{ :; }}
HOST=atlas-01; OS='Ubuntu 24.04 LTS'; ARCH=x86_64; ENVIRONMENT='virtual machine'; INIT=systemd
CPU_MODEL='8-core server processor'; PACKAGE_MANAGER=apt-get
CPU_PCT=37; CPU_WAIT=2; CORES=8; MEM_PCT=62; SWAP_PCT=4
MEM_TOTAL=34359738368; MEM_USED=21303037788; MEM_AVAILABLE=13056700580; MEM_CACHED=4294967296
SWAP_TOTAL=4294967296; SWAP_USED=171798691
NET_RX=7549747; NET_TX=1258291; DISK_READ=12582912; DISK_WRITE=4194304
UPTIME=532920; LOAD='1.24 0.88 0.72'; SAMPLE=42; PROCESS_COUNT=184; ZOMBIES=0
CPU_HISTORY=(8 9 12 16 23 38 41 32 25 18 20 14 19 28 34 43 55 61 49 35 28 21 25 17 13 8 9 12 17 22 19 24 31 47 52 66 59 41 32 28 21 19 14 18 23 27 34 46 51 39 33 29 22 24 31 44 48 41 39 37)
for ((i=0;i<60;i++)); do
    MEM_HISTORY+=("$((54+i/7))")
    NET_HISTORY+=("$(((CPU_HISTORY[i]+i%11)*131072))")
    IO_HISTORY+=("$(((CPU_HISTORY[59-i]+i%7)*524288))")
done
CPU_ROWS=('cpu|37|2' 'cpu0|61|1' 'cpu1|42|0' 'cpu2|35|2' 'cpu3|22|0' 'cpu4|54|4' 'cpu5|17|0' 'cpu6|40|2' 'cpu7|25|1')
NET_ROWS=('eth0|up|7549747|1258291|2340000000|420000000|0|0' 'lo|unknown|0|0|0|0|0|0')
IO_ROWS=('nvme0n1|12582912|4194304|18|2')
FS_ROWS=('/dev/nvme0n1p2|500000000000|255000000000|245000000000|51|12|/')
PROCESS_ROWS=('2841|R|28|734003200|postgres' '3920|S|12|268435456|node' '1082|S|8|67108864|nginx' '4421|S|5|134217728|redis-server' '5612|R|2|16777216|infoReport.sh' '892|S|1|41943040|containerd' '310|S|0|12582912|systemd-journald')
SERVICE_ROWS=('nginx.service|active / running' 'postgresql.service|active / running')
CONTAINER_ROWS=('Docker (local)' 'api | app:latest | Up 6 days')
ADDRESS_ROWS=('2: eth0 inet 10.0.0.12/24 scope global eth0')
SOCKET_ROWS=('tcp LISTEN 0 128 0.0.0.0:443 0.0.0.0:*')
init_ui; draw_screen
"""
    return shell(fixture, env=dict(os.environ, TERM="xterm-256color", COLORTERM="truecolor"))


def decode_frame(frame, columns, rows):
    """Small strict ANSI decoder for our cursor/style output; also checks bounds."""
    default_fg, default_bg = (215, 227, 242), (11, 18, 27)
    fg, bg, bold, reverse = default_fg, default_bg, False, False
    cells = [[(" ", fg, bg, False) for _ in range(columns)] for _ in range(rows)]
    y = x = pos = 0
    ansi = re.compile(r"\x1b\[([0-9;?]*)([A-Za-z])")
    basic = [(0, 0, 0), (190, 60, 60), (80, 170, 80), (190, 160, 70), (80, 120, 190), (170, 100, 180), (80, 180, 180), (220, 220, 220)]
    while pos < len(frame):
        if frame[pos] == "\x1b":
            match = ansi.match(frame, pos)
            if not match:
                raise AssertionError(f"Unrecognized escape: {frame[pos:pos+20]!r}")
            codes = [int(n) if n else 0 for n in match[1].split(";")]
            if match[2] == "H":
                y, x = codes[0] - 1, codes[1] - 1
            elif match[2] == "K" and codes == [2]:
                cells[y] = [(" ", fg, bg, bold) for _ in range(columns)]
            elif match[2] == "m":
                i = 0
                while i < len(codes):
                    code = codes[i]
                    if code == 0:
                        fg, bg, bold, reverse = default_fg, default_bg, False, False
                    elif code == 1:
                        bold = True
                    elif code == 7:
                        reverse = True
                    elif code in (38, 48) and codes[i + 1] == 2:
                        rgb = tuple(codes[i + 2:i + 5])
                        if code == 38:
                            fg = rgb
                        else:
                            bg = rgb
                        i += 4
                    elif 30 <= code <= 37:
                        fg = basic[code - 30]
                    elif 40 <= code <= 47:
                        bg = basic[code - 40]
                    else:
                        raise AssertionError(f"Unrecognized SGR: {codes}")
                    i += 1
            else:
                raise AssertionError(f"Unexpected ANSI operation: {match[0]!r}")
            pos = match.end()
            continue
        if not (0 <= x < columns - 1 and 0 <= y < rows):
            raise AssertionError(f"Out-of-bounds cell {x},{y} on {columns}x{rows}")
        cells[y][x] = (frame[pos], bg if reverse else fg, fg if reverse else bg, bold)
        x += 1
        pos += 1
    return cells


class Layout(unittest.TestCase):
    def test_layouts_fit_terminal_in_unicode_ascii_and_monochrome(self):
        for columns, rows in [(55, 12), (79, 24), (80, 24), (120, 36)]:
            for ascii_mode, color in [(False, True), (True, True), (True, False)]:
                with self.subTest(size=(columns, rows), ascii=ascii_mode, color=color):
                    frame = render_fixture(columns, rows, ascii_mode=ascii_mode, color=color)
                    cells = decode_frame(frame, columns, rows)
                    text = "\n".join("".join(cell[0] for cell in row) for row in cells)
                    self.assertIn("SERVER / INFO REPORT", text)
                    self.assertIn("sample 42", text)
                    self.assertIn("q quit", text)
                    if columns >= 80:
                        self.assertIn("STORAGE I/O", text)
                        self.assertIn("postgres", text)
                    if ascii_mode:
                        self.assertTrue(frame.isascii())

    def test_all_views_and_themes_render(self):
        for page in range(7):
            for theme in ("midnight", "nord", "light"):
                with self.subTest(page=page, theme=theme):
                    decode_frame(render_fixture(theme=theme, page=page), 120, 36)


if __name__ == "__main__":
    unittest.main(verbosity=2)
