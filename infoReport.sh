#!/usr/bin/env bash
# ServerInfoReport 4.0 -- a single-file, read-only Linux monitor.
# Author: 0xPacman | MIT
# Requires Bash 4+, awk and common Linux utilities. No Python, jq, bc or dialog.

UI_LOCALE=${LC_ALL:-${LC_CTYPE:-${LANG:-C}}}
export LC_ALL=C
if ((BASH_VERSINFO[0] < 4)); then printf 'infoReport requires Bash 4 or newer\n' >&2; exit 2; fi
VERSION=4.0.0
MODE=auto FORMAT=txt OUTPUT='' INTERVAL=2 COUNT=0 QUIET=0 COLOR=1
THEME=midnight ASCII=0 FRAME='' UI_BASE='' UI_LEVEL=16
declare -A UI_COLORS=()
declare -a GRAPH_CHARS=(' ' '.' ':' '-' '=' '+' '#' '%' '@')
BOX_H='-' BOX_V='|' BOX_TL='+' BOX_TR='+' BOX_BL='+' BOX_BR='+'
CPU_LIMIT=80 MEM_LIMIT=85 DISK_LIMIT=90 ALERTS_ENABLED=1
SERVICES='' CONTAINERS=0 SECURITY=0
PROC=/proc SYS=/sys
CPU_PCT=null CPU_WAIT=null MEM_PCT=null SWAP_PCT=null
MEM_TOTAL=0 MEM_USED=0 MEM_AVAILABLE=0 MEM_CACHED=0 SWAP_TOTAL=0 SWAP_USED=0
NOW_MS=0 PREV_MS=0 ELAPSED_MS=0 UPTIME=0 LOAD='N/A' CORES=1
HOST='' OS='' KERNEL='' ARCH='' CPU_MODEL='' ENVIRONMENT='' INIT='' PACKAGE_MANAGER=''
PAGE=0 SCROLL=0 PAUSED=0 SORT=cpu FILTER='' MESSAGE='' SAMPLE=0 STATUS=0
TERM_ACTIVE=0 SAVED_STTY='' ROWS=24 COLS=80 HELP=0 REDRAW=1
LAST_SLOW=-1 LAST_DETAIL=-1 PAGE_SIZE=4096 CLK_TCK=100
declare -a CPU_ROWS=() NET_ROWS=() IO_ROWS=() FS_ROWS=() PROCESS_ROWS=()
declare -a SERVICE_ROWS=() CONTAINER_ROWS=() SENSOR_ROWS=() ALERT_ROWS=()
declare -a ADDRESS_ROWS=() SOCKET_ROWS=() SECURITY_ROWS=() NOTES=() LINES=()
declare -a CPU_HISTORY=() MEM_HISTORY=() NET_HISTORY=() IO_HISTORY=()
declare -a PAGES=('Overview' 'CPU / RAM' 'Storage' 'Network' 'Processes' 'Services' 'System')
declare -A PREV_CPU=() PREV_NET=() PREV_IO=() PREV_PROCESS=()
declare -A SEEN_CPU=() SEEN_NET=() SEEN_IO=()
NET_RX=0 NET_TX=0 DISK_READ=0 DISK_WRITE=0 PROCESS_COUNT=0 ZOMBIES=0
CGROUP_MEMORY='N/A' CGROUP_CPU='N/A' PRESSURE=

fail() { printf 'infoReport: %s\n' "$*" >&2; return 2; }
has() { command -v "$1" >/dev/null 2>&1; }
uint() { [[ $1 =~ ^[0-9]+$ ]]; }
safe() { REPLY=${1//[^[:print:]]/?}; }
read_file() { REPLY=; [[ -r $1 ]] && IFS= read -r REPLY < "$1"; return 0; }
bounded() {
    # Optional commands may contact daemons. Never run them without a deadline.
    has timeout || return 125
    timeout -k 1 3 "$@" 2>/dev/null
}
help_text() {
    cat <<'HELP'
ServerInfoReport -- live Linux monitoring in one Bash script
Usage: ./infoReport.sh [OPTIONS]

  --tui, --monitor       Interactive dashboard (default on a terminal)
  --report              One snapshot (default when redirected)
  --watch               Repeated reports; JSON becomes one object per line
  --interval N          Refresh/sample interval, 1..3600 seconds (default 2)
  --count N             Stop after N samples (0 means unlimited)
  -f, --format FORMAT   txt, json or html; selects report mode
  -o, --output FILE     Atomically write a report; watch replaces it each time
  -q, --quiet           Only status on stdout (exports remain complete)
  -d, --detailed        Include passive security and container information
  --services LIST      Comma-separated systemd/OpenRC service names
  --containers         Query local Docker/Podman containers (optional)
  --security-scan      Include passive local security information
  --health-check       One report with threshold exit status
  --cpu-threshold N    CPU warning percentage, 1..100 (default 80)
  --mem-threshold N    Memory warning percentage, 1..100 (default 85)
  --disk-threshold N   Disk/inode warning percentage, 1..100 (default 90)
  --no-alerts           Disable resource threshold warnings
  --no-color           Monochrome TUI (also honors NO_COLOR)
  --theme NAME         midnight, nord or light (default midnight)
  --ascii              Plain ASCII borders/graphs for limited terminals
  --no-log             Compatibility option; no implicit logging is performed
  -h, --help            Show help
  --version            Show version

Keys: 1..7 pages | Tab/left/right navigate | j/k/up/down scroll | PgUp/PgDn
      Space pause | c/m/p process sort | / process filter | r refresh details
      e export JSON | t cycle theme | ? help | q quit

Exit: 0 no threshold warnings, 1 active warnings, 2 usage/collection/I/O error.
Requires Linux, Bash 4+, awk, sort, df, date, sleep, uname. No root required.
HELP
}
parse_args() {
    local key value
    while (($#)); do
        key=$1
        case $key in
            --interval|--count|-f|--format|-o|--output|--services|--theme|--cpu-threshold|--mem-threshold|--disk-threshold)
                if (($# < 2)) || [[ -z $2 || $2 == --* ]]; then fail "missing value for $key"; return 2; fi
                value=$2
                case $key in
                    --interval|--count|--cpu-threshold|--mem-threshold|--disk-threshold)
                        [[ $value =~ ^[0-9]{1,7}$ ]] || { fail "invalid number for $key: $value"; return 2; }
                        value=$((10#$value)) ;;
                esac
                case $key in
                    --interval) ((value >= 1 && value <= 3600)) || { fail 'interval must be 1..3600'; return 2; }; INTERVAL=$value ;;
                    --count) COUNT=$value ;;
                    -f|--format) FORMAT=$value; [[ $FORMAT == txt || $FORMAT == json || $FORMAT == html ]] || { fail 'format must be txt, json or html'; return 2; }; [[ $MODE == auto ]] && MODE=report ;;
                    -o|--output) OUTPUT=$value; [[ $MODE == auto ]] && MODE=report ;;
                    --services) [[ $value =~ ^[a-zA-Z0-9_.@:-]+(,[a-zA-Z0-9_.@:-]+)*$ && ${#value} -le 1024 ]] || { fail 'invalid service list'; return 2; }; SERVICES=$value ;;
                    --theme) case $value in midnight|nord|light) THEME=$value;; *) fail 'theme must be midnight, nord or light'; return 2;; esac ;;
                    *) ((value >= 1 && value <= 100)) || { fail 'threshold must be 1..100'; return 2; }
                       case $key in --cpu-threshold) CPU_LIMIT=$value;; --mem-threshold) MEM_LIMIT=$value;; --disk-threshold) DISK_LIMIT=$value;; esac ;;
                esac
                shift 2 ;;
            --tui|--monitor) MODE=tui; shift ;;
            --report|--health-check) MODE=report; shift ;;
            --watch) MODE=watch; shift ;;
            -q|--quiet) QUIET=1; [[ $MODE == auto ]] && MODE=report; shift ;;
            -d|--detailed) SECURITY=1; CONTAINERS=1; shift ;;
            --containers) CONTAINERS=1; shift ;;
            --security-scan) SECURITY=1; shift ;;
            --no-alerts) ALERTS_ENABLED=0; shift ;;
            --no-color) COLOR=0; shift ;;
            --ascii) ASCII=1; shift ;;
            --no-log) shift ;;
            --performance-test) fail 'benchmarks were retired in v4; this monitor only observes the system'; return 2 ;;
            -h|--help) help_text; return 10 ;;
            --version) printf 'ServerInfoReport %s\n' "$VERSION"; return 10 ;;
            *) fail "unknown option: $key"; return 2 ;;
        esac
    done
    [[ -n ${NO_COLOR+x} ]] && COLOR=0
    return 0
}
detect_system() {
    local key value candidate
    HOST=$(uname -n); KERNEL=$(uname -r); ARCH=$(uname -m); OS=Linux
    # Parse os-release as data; never source executable distribution metadata.
    for candidate in /etc/os-release /usr/lib/os-release; do
        [[ -r $candidate ]] || continue
        while IFS='=' read -r key value; do
            [[ $key == PRETTY_NAME ]] || continue
            value=${value#\"}; value=${value%\"}; value=${value#\'}; value=${value%\'}
            OS=$value
        done < "$candidate"
        break
    done
    CPU_MODEL=$(awk -F ': *' '/^(model name|Hardware|Processor)[[:space:]]*:/ {print $2; exit}' "$PROC/cpuinfo" 2>/dev/null)
    [[ -n $CPU_MODEL ]] || CPU_MODEL=$ARCH
    CORES=$(awk '/^cpu[0-9]+ / {n++} END {print n+0}' "$PROC/stat")
    ((CORES > 0)) || CORES=1
    if has getconf; then
        value=$(getconf PAGESIZE 2>/dev/null); uint "$value" && PAGE_SIZE=$value
        value=$(getconf CLK_TCK 2>/dev/null); uint "$value" && ((value > 0)) && CLK_TCK=$value
    fi
    INIT=unknown
    [[ -d /run/systemd/system ]] && has systemctl && INIT=systemd
    [[ $INIT == unknown && -d /run/openrc ]] && has rc-status && INIT=OpenRC
    if [[ $INIT == unknown ]]; then read_file "$PROC/1/comm"; INIT=${REPLY:-unknown}; fi
    PACKAGE_MANAGER=unknown
    for candidate in apt-get dnf yum zypper pacman apk xbps-query emerge; do
        if has "$candidate"; then PACKAGE_MANAGER=$candidate; break; fi
    done
    ENVIRONMENT='bare metal / unknown'
    [[ -d /sys/hypervisor ]] && ENVIRONMENT='virtual machine / unknown'
    [[ -f /.dockerenv || -f /run/.containerenv ]] && ENVIRONMENT=container
    [[ ${KERNEL,,} == *microsoft* ]] && ENVIRONMENT=WSL
    if has systemd-detect-virt; then
        value=$(bounded systemd-detect-virt) && [[ -n $value && $value != none ]] && ENVIRONMENT=$value
    fi
    has timeout || NOTES+=('timeout missing: optional daemon queries and filesystem probes are disabled')
    [[ -r $PROC/pressure/cpu ]] || NOTES+=('Kernel pressure-stall information is unavailable')
    [[ -r $SYS/fs/cgroup/cgroup.controllers ]] || NOTES+=('cgroup v2 limits unavailable; CPU/RAM metrics describe the visible host')
}
clock_ms() {
    local up whole fraction
    read -r up _ < "$PROC/uptime"
    whole=${up%.*}; fraction=${up#*.}000
    NOW_MS=$((10#$whole * 1000 + 10#${fraction:0:3})); UPTIME=$whole
}
collect_cpu() {
    local name user nice system idle wait irq soft steal rest total delta idle_delta wait_delta pct wpct
    CPU_ROWS=(); SEEN_CPU=(); CPU_PCT=null; CPU_WAIT=null
    while read -r name user nice system idle wait irq soft steal rest; do
        [[ $name == cpu* ]] || continue
        [[ $name == cpu || $name =~ ^cpu[0-9]+$ ]] || continue
        total=$((user + nice + system + idle + ${wait:-0} + ${irq:-0} + ${soft:-0} + ${steal:-0}))
        pct=null; wpct=null
        if [[ -n ${PREV_CPU[$name]+x} ]]; then
            read -r delta idle_delta wait_delta <<< "${PREV_CPU[$name]}"
            delta=$((total-delta)); idle_delta=$((idle+${wait:-0}-idle_delta)); wait_delta=$((${wait:-0}-wait_delta))
            if ((delta > 0 && idle_delta >= 0 && idle_delta <= delta && wait_delta >= 0)); then
                pct=$(((delta-idle_delta)*100/delta)); wpct=$((wait_delta*100/delta))
            fi
        fi
        SEEN_CPU[$name]="$total $((idle+${wait:-0})) ${wait:-0}"
        CPU_ROWS+=("$name|$pct|$wpct")
        [[ $name == cpu ]] && { CPU_PCT=$pct; CPU_WAIT=$wpct; }
    done < "$PROC/stat"
    PREV_CPU=(); for name in "${!SEEN_CPU[@]}"; do PREV_CPU[$name]=${SEEN_CPU[$name]}; done
    CORES=$((${#CPU_ROWS[@]}-1)); ((CORES > 0)) || CORES=1
    read -r LOAD < "$PROC/loadavg"
    LOAD=${LOAD% *}; LOAD=${LOAD% *}
}
collect_memory() {
    local key value rest available=-1 free=0 buffers=0 cached=0 reclaim=0 shmem=0 swap_free=0
    MEM_TOTAL=0; SWAP_TOTAL=0; MEM_PCT=null; SWAP_PCT=null
    while read -r key value rest; do
        case $key in
            MemTotal:) MEM_TOTAL=$((value*1024));; MemAvailable:) available=$((value*1024));;
            MemFree:) free=$((value*1024));; Buffers:) buffers=$((value*1024));;
            Cached:) cached=$((value*1024));; SReclaimable:) reclaim=$((value*1024));;
            Shmem:) shmem=$((value*1024));; SwapTotal:) SWAP_TOTAL=$((value*1024));;
            SwapFree:) swap_free=$((value*1024));;
        esac
    done < "$PROC/meminfo"
    ((available >= 0)) || available=$((free+buffers+cached+reclaim-shmem))
    ((available < 0)) && available=0
    ((available > MEM_TOTAL)) && available=$MEM_TOTAL
    MEM_AVAILABLE=$available; MEM_USED=$((MEM_TOTAL-available)); MEM_CACHED=$((cached+reclaim))
    SWAP_USED=$((SWAP_TOTAL-swap_free))
    ((MEM_TOTAL > 0)) && MEM_PCT=$((MEM_USED*100/MEM_TOTAL))
    ((SWAP_TOTAL > 0)) && SWAP_PCT=$((SWAP_USED*100/SWAP_TOTAL))
    return 0
}
rate() {
    REPLY=null
    if ((ELAPSED_MS > 0 && $1 >= $2)); then REPLY=$((($1-$2)*1000/ELAPSED_MS)); fi
}
collect_network() {
    local line name fields rx tx rxrate txrate errors drops state old_rx old_tx
    local -a numbers
    NET_ROWS=(); SEEN_NET=(); NET_RX=0; NET_TX=0
    while IFS= read -r line; do
        [[ $line == *:* ]] || continue
        name=${line%%:*}; name=${name//[[:space:]]/}; fields=${line#*:}
        read -r -a numbers <<< "$fields"
        ((${#numbers[@]} >= 16)) || continue
        rx=${numbers[0]}; tx=${numbers[8]}; errors=$((numbers[2]+numbers[10])); drops=$((numbers[3]+numbers[11]))
        rxrate=null; txrate=null
        if [[ -n ${PREV_NET[$name]+x} ]]; then
            read -r old_rx old_tx <<< "${PREV_NET[$name]}"
            rate "$rx" "$old_rx"; rxrate=$REPLY; rate "$tx" "$old_tx"; txrate=$REPLY
        fi
        SEEN_NET[$name]="$rx $tx"
        read_file "$SYS/class/net/$name/operstate"; state=${REPLY:-unknown}
        safe "$name"; NET_ROWS+=("${REPLY//|/?}|$state|$rxrate|$txrate|$rx|$tx|$errors|$drops")
        if [[ $name != lo ]]; then
            [[ $rxrate != null ]] && NET_RX=$((NET_RX+rxrate))
            [[ $txrate != null ]] && NET_TX=$((NET_TX+txrate))
        fi
    done < "$PROC/net/dev"
    PREV_NET=(); for name in "${!SEEN_NET[@]}"; do PREV_NET[$name]=${SEEN_NET[$name]}; done
}
collect_io() {
    local _major _minor name _reads _merges sectors_r _ms_r _writes _merges_w sectors_w _ms_w running ms_io rest
    local old_r old_w old_ms rr wr busy
    IO_ROWS=(); SEEN_IO=(); DISK_READ=0; DISK_WRITE=0
    while read -r _major _minor name _reads _merges sectors_r _ms_r _writes _merges_w sectors_w _ms_w running ms_io rest; do
        [[ -d $SYS/block/$name ]] || continue
        [[ $name == loop* || $name == ram* ]] && continue
        rr=null; wr=null; busy=null
        if [[ -n ${PREV_IO[$name]+x} ]]; then
            read -r old_r old_w old_ms <<< "${PREV_IO[$name]}"
            rate "$((sectors_r*512))" "$((old_r*512))"; rr=$REPLY
            rate "$((sectors_w*512))" "$((old_w*512))"; wr=$REPLY
            if ((ELAPSED_MS > 0 && ms_io >= old_ms)); then
                busy=$(((ms_io-old_ms)*100/ELAPSED_MS)); ((busy > 100)) && busy=100
            fi
        fi
        SEEN_IO[$name]="$sectors_r $sectors_w $ms_io"
        IO_ROWS+=("$name|$rr|$wr|$busy|$running")
        [[ $rr != null ]] && DISK_READ=$((DISK_READ+rr))
        [[ $wr != null ]] && DISK_WRITE=$((DISK_WRITE+wr))
    done < "$PROC/diskstats"
    PREV_IO=(); for name in "${!SEEN_IO[@]}"; do PREV_IO[$name]=${SEEN_IO[$name]}; done
}
collect_processes() {
    local path line pid name tail ticks start rss pct old_ticks old_start key
    local -a fields rows=()
    local -A current=()
    PROCESS_COUNT=0; ZOMBIES=0
    for path in "$PROC"/[0-9]*/stat; do
        # Processes can disappear between enumeration and reading.
        { IFS= read -r line < "$path"; } 2>/dev/null || continue
        pid=${line%% *}; uint "$pid" || continue
        name=${line#*\(}; name=${name%\)*}; tail=${line##*\) }
        read -r -a fields <<< "$tail"
        ((${#fields[@]} >= 22)) || continue
        if ! uint "${fields[11]}" || ! uint "${fields[12]}" || ! uint "${fields[19]}"; then continue; fi
        ticks=$((fields[11]+fields[12])); start=${fields[19]}; rss=${fields[21]}; pct=null
        [[ $rss =~ ^-?[0-9]+$ ]] || continue
        ((rss < 0)) && rss=0
        if [[ -n ${PREV_PROCESS[$pid]+x} ]]; then
            read -r old_ticks old_start <<< "${PREV_PROCESS[$pid]}"
            if [[ $start == "$old_start" ]] && ((ELAPSED_MS > 0 && ticks >= old_ticks)); then
                pct=$(((ticks-old_ticks)*100000/(CLK_TCK*ELAPSED_MS)))
            fi
        fi
        current[$pid]="$ticks $start"
        safe "$name"; name=${REPLY//|/?}
        rows+=("$pid|${fields[0]}|$pct|$((rss*PAGE_SIZE))|$name")
        ((PROCESS_COUNT+=1)); [[ ${fields[0]} == Z ]] && ((ZOMBIES+=1))
    done
    PREV_PROCESS=(); for key in "${!current[@]}"; do PREV_PROCESS[$key]=${current[$key]}; done
    PROCESS_ROWS=("${rows[@]}")
}

collect_filesystems() {
    local blocks inodes _device mount type rest block_status=0 inode_status=0
    local -a mounts=()
    local -A seen=()
    # BusyBox df has no -l. Select local mounts before calling either df variant.
    if [[ -r $PROC/mounts ]]; then
        while read -r _device mount type rest; do
            case $type in
                nfs*|cifs|smb*|9p|ceph|afs|glusterfs|lustre|fuse.*|autofs) continue ;;
                proc|sysfs|devpts|cgroup*|securityfs|pstore|debugfs|tracefs|configfs|hugetlbfs|mqueue|rpc_pipefs|binfmt_misc|nsfs|bpf|efivarfs|fusectl) continue ;;
            esac
            printf -v mount '%b' "$mount"
            [[ $mount == /* && -z ${seen[$mount]+x} ]] || continue
            mounts+=("$mount"); seen[$mount]=1
        done < "$PROC/mounts"
    fi
    ((${#mounts[@]})) || mounts=(/)
    FS_ROWS=()
    # df may emit useful rows and still fail for an inaccessible/disappearing
    # mount (BusyBox also rejects some file bind mounts). Preserve partial data.
    blocks=$(bounded df -P -k -- "${mounts[@]}") || block_status=$?
    inodes=$(bounded df -P -i -- "${mounts[@]}") || inode_status=$?
    # Locate the percentage column rather than splitting mount paths on spaces.
    mapfile -t FS_ROWS < <(awk '
        function join(a,b, s,j) {s=$a; for(j=a+1;j<=b;j++) s=s " " $j; gsub(/\|/, "?", s); return s}
        /^__BLOCKS__$/ {block=1; next}
        {for(i=5;i<NF;i++) if($i ~ /^[0-9]+%$/ && $(i-1) ~ /^-?[0-9]+$/) {
            mount=join(i+1,NF); pct=$i; sub(/%$/, "", pct)
            if(!block) inode[mount]=pct
            else printf "%s|%.0f|%.0f|%.0f|%s|%s|%s\n", join(1,i-4), $(i-3)*1024, $(i-2)*1024, $(i-1)*1024, pct, (mount in inode ? inode[mount] : "null"), mount
            break
        }}' <<< "$inodes"$'\n__BLOCKS__\n'"$blocks")
    if ((${#FS_ROWS[@]} == 0)); then
        FS_ROWS=('unavailable|null|null|null|null|null|Local filesystem query unavailable or timed out')
    elif ((block_status != 0 || inode_status != 0)); then
        FS_ROWS+=('partial|null|null|null|null|null|Some filesystem/inode queries failed; showing available data')
    fi
}
collect_sensors() {
    local input value label chip
    SENSOR_ROWS=()
    for input in "$SYS"/class/hwmon/hwmon*/temp*_input; do
        [[ -r $input ]] || continue
        read_file "$input"; value=$REPLY
        [[ $value =~ ^-?[0-9]+$ ]] || continue
        ((value >= -100000 && value <= 200000)) || continue
        read_file "${input%/*}/name"; chip=${REPLY:-sensor}
        read_file "${input%_input}_label"; label=${REPLY:-${input##*/}}
        safe "$chip/$label"; SENSOR_ROWS+=("${REPLY//|/?}|$value")
    done
    if ((${#SENSOR_ROWS[@]} == 0)); then
        for input in "$SYS"/class/thermal/thermal_zone*/temp; do
            [[ -r $input ]] || continue
            read_file "$input"; value=$REPLY
            [[ $value =~ ^-?[0-9]+$ ]] || continue
            ((value >= -100000 && value <= 200000)) || continue
            read_file "${input%/*}/type"; safe "${REPLY:-thermal}"
            SENSOR_ROWS+=("${REPLY//|/?}|$value")
        done
    fi
}
collect_pressure_cgroup() {
    local resource line path='' current limit quota period
    PRESSURE=
    for resource in cpu memory io; do
        [[ -r $PROC/pressure/$resource ]] || continue
        while IFS= read -r line; do PRESSURE+="$resource $line"$'\n'; done < "$PROC/pressure/$resource"
    done
    if [[ -r $PROC/self/cgroup ]]; then
        while IFS=: read -r resource line current; do [[ $resource == 0 ]] && path=$current; done < "$PROC/self/cgroup"
    fi
    CGROUP_MEMORY='N/A'; CGROUP_CPU='N/A'
    [[ $path == /* && $path != *..* ]] || return 0
    path="$SYS/fs/cgroup$path"
    # A cgroup namespace can expose its own root at /sys/fs/cgroup.
    [[ -r $path/memory.current ]] || path="$SYS/fs/cgroup"
    if [[ -r $path/memory.current && -r $path/memory.max ]]; then
        read_file "$path/memory.current"; current=$REPLY
        read_file "$path/memory.max"; limit=$REPLY
        CGROUP_MEMORY="$current / $limit bytes"
    fi
    if [[ -r $path/cpu.max ]]; then
        read -r quota period < "$path/cpu.max"
        CGROUP_CPU="quota $quota / period $period us"
    fi
}
collect_details() {
    local raw line name load active sub rest service state engine
    local -a requested=()
    local -A service_map=()
    ADDRESS_ROWS=(); SOCKET_ROWS=(); SERVICE_ROWS=(); CONTAINER_ROWS=(); SECURITY_ROWS=()
    if has ip && raw=$(bounded ip -o address show); then
        mapfile -t ADDRESS_ROWS <<< "$raw"
    elif has hostname && raw=$(bounded hostname -I); then
        ADDRESS_ROWS=("Addresses: $raw")
    else ADDRESS_ROWS=('Address details unavailable (install iproute2)'); fi
    if has ss && raw=$(bounded ss -H -lntu); then
        [[ -n $raw ]] && mapfile -t SOCKET_ROWS <<< "$raw"
    elif has netstat && raw=$(bounded netstat -lntu); then
        mapfile -t SOCKET_ROWS <<< "$raw"
    else SOCKET_ROWS=('Listening sockets unavailable (install iproute2)'); fi

    if [[ $INIT == systemd ]]; then
        if raw=$(bounded systemctl list-units --all --type=service --no-legend --plain --no-pager); then
            while read -r name load active sub rest; do
                [[ $name == *.service ]] || continue
                service_map[$name]="$load / $active / $sub"
                SERVICE_ROWS+=("$name|$active / $sub")
            done <<< "$raw"
        else SERVICE_ROWS=('systemd|unavailable or timed out'); fi
    elif [[ $INIT == OpenRC ]]; then
        if raw=$(bounded rc-status -a --nocolor); then
            while IFS= read -r line; do
                [[ $line == *'['*']'* ]] || continue
                read -r name rest <<< "$line"
                state=${line#*[}; state=${state%%]*}; state=${state//[[:space:]]/}
                service_map[$name]=$state; SERVICE_ROWS+=("$name|$state")
            done <<< "$raw"
        else SERVICE_ROWS=('OpenRC|unavailable or timed out'); fi
    else SERVICE_ROWS=("$INIT|Service inspection supports systemd and OpenRC"); fi
    if [[ -n $SERVICES ]]; then
        SERVICE_ROWS=(); IFS=, read -r -a requested <<< "$SERVICES"
        for service in "${requested[@]}"; do
            name=$service
            [[ $INIT == systemd && $name != *.service ]] && name+=.service
            SERVICE_ROWS+=("$name|${service_map[$name]:-unknown / not loaded}")
        done
    fi
    if ((CONTAINERS)); then
        engine=
        if has docker && [[ -S /var/run/docker.sock ]]; then
            engine=Docker
            raw=$(bounded docker --host unix:///var/run/docker.sock ps -a --format '{{.Names}} | {{.Image}} | {{.Status}}') || raw='Unavailable: socket permissions, daemon failure or timeout'
        elif has podman; then
            engine=Podman
            raw=$(bounded podman --remote=false ps -a --format '{{.Names}} | {{.Image}} | {{.Status}}') || raw='Unavailable: permissions, daemon failure or timeout'
        fi
        if [[ -n $engine ]]; then
            CONTAINER_ROWS=("$engine (local)")
            if [[ -n $raw ]]; then while IFS= read -r line; do CONTAINER_ROWS+=("$line"); done <<< "$raw"
            else CONTAINER_ROWS+=('No containers found'); fi
        else CONTAINER_ROWS=('No accessible local Docker socket or Podman command'); fi
    else CONTAINER_ROWS=('Use --containers to include local Docker / Podman containers'); fi
    if ((SECURITY)); then
        SECURITY_ROWS=('Passive observations; this is not a security audit.')
        for name in kernel/randomize_va_space kernel/dmesg_restrict kernel/kptr_restrict net/ipv4/ip_forward; do
            read_file "$PROC/sys/$name"; SECURITY_ROWS+=("$name = ${REPLY:-unavailable}")
        done
        read_file "$SYS/fs/selinux/enforce"; [[ -n $REPLY ]] && SECURITY_ROWS+=("SELinux enforce = $REPLY")
        read_file "$SYS/module/apparmor/parameters/enabled"; [[ -n $REPLY ]] && SECURITY_ROWS+=("AppArmor enabled = $REPLY")
        SECURITY_ROWS+=('SSH effective policy and firewall rules are not inferred from missing data.')
    fi
}
check_alerts() {
    local row name total used avail pct inode mount
    ALERT_ROWS=(); STATUS=0
    ((ALERTS_ENABLED)) || return 0
    [[ $CPU_PCT != null ]] && ((CPU_PCT >= CPU_LIMIT)) && ALERT_ROWS+=("CPU utilization $CPU_PCT% >= $CPU_LIMIT%")
    [[ $MEM_PCT != null ]] && ((MEM_PCT >= MEM_LIMIT)) && ALERT_ROWS+=("Memory utilization $MEM_PCT% >= $MEM_LIMIT%")
    for row in "${FS_ROWS[@]}"; do
        IFS='|' read -r name total used avail pct inode mount <<< "$row"
        [[ $pct != null ]] && ((pct >= DISK_LIMIT)) && ALERT_ROWS+=("Filesystem $mount is $pct% full")
        [[ $inode != null ]] && ((inode >= DISK_LIMIT)) && ALERT_ROWS+=("Inodes on $mount are $inode% used")
    done
    ((${#ALERT_ROWS[@]} > 0)) && STATUS=1
    return 0
}
collect_fast() {
    [[ -r $PROC/stat && -r $PROC/meminfo && -r $PROC/uptime ]] || { fail 'Linux procfs is unavailable'; return 2; }
    clock_ms; ELAPSED_MS=$((NOW_MS-PREV_MS))
    ((PREV_MS > 0)) || ELAPSED_MS=0
    collect_cpu; collect_memory
    [[ -r $PROC/net/dev ]] && collect_network
    [[ -r $PROC/diskstats ]] && collect_io
    collect_processes; collect_pressure_cgroup
    PREV_MS=$NOW_MS
    return 0
}
collect_snapshot() {
    collect_fast || return 2
    if ((LAST_SLOW < 0 || NOW_MS-LAST_SLOW >= 15000)); then
        collect_filesystems; collect_sensors; LAST_SLOW=$NOW_MS
    fi
    if ((LAST_DETAIL < 0 || NOW_MS-LAST_DETAIL >= 30000)); then
        collect_details; LAST_DETAIL=$NOW_MS
    fi
    check_alerts; ((SAMPLE+=1))
    CPU_HISTORY+=("$CPU_PCT"); MEM_HISTORY+=("$MEM_PCT")
    NET_HISTORY+=("$((NET_RX+NET_TX))"); IO_HISTORY+=("$((DISK_READ+DISK_WRITE))")
    if ((${#CPU_HISTORY[@]} > 60)); then
        CPU_HISTORY=("${CPU_HISTORY[@]:${#CPU_HISTORY[@]}-60}"); MEM_HISTORY=("${MEM_HISTORY[@]:${#MEM_HISTORY[@]}-60}")
        NET_HISTORY=("${NET_HISTORY[@]:${#NET_HISTORY[@]}-60}"); IO_HISTORY=("${IO_HISTORY[@]:${#IO_HISTORY[@]}-60}")
    fi
    return 0
}

# Rendering is separate from collection: navigation and exports reuse a snapshot.
human() {
    local n=$1 unit=0 tenth
    local -a units=(B KiB MiB GiB TiB PiB)
    [[ $n != null ]] || { REPLY='N/A'; return; }
    tenth=$((n*10))
    while ((tenth >= 10240 && unit < 5)); do tenth=$((tenth/1024)); ((unit+=1)); done
    REPLY="$((tenth/10)).$((tenth%10))${units[unit]}"
}
bar() {
    local pct=$1 width=${2:-24} filled empty
    if [[ $pct == null ]]; then REPLY='[ data unavailable ]'; return; fi
    filled=$((pct*width/100)); ((filled > width)) && filled=$width
    printf -v filled '%*s' "$filled" ''; filled=${filled// /#}
    printf -v empty '%*s' "$((width-${#filled}))" ''; empty=${empty// /-}
    printf -v REPLY '[%s%s] %3d%%' "$filled" "$empty" "$pct"
}
spark() {
    local maximum=$1 value index result='' chars=' .:-=+*#%@'
    shift
    if ((maximum == 0)); then for value in "$@"; do [[ $value != null ]] && ((value > maximum)) && maximum=$value; done; fi
    ((maximum > 0)) || maximum=1
    for value in "$@"; do
        if [[ $value == null ]]; then result+='?'; else
            index=$((value*9/maximum)); ((index > 9)) && index=9; result+=${chars:index:1}
        fi
    done
    REPLY=$result
}
add() { LINES+=("$*"); }
heading() { add ""; add "-- $* --"; }
sorted_processes() {
    local order='-k3,3nr' row
    case $SORT in mem) order='-k4,4nr';; pid) order='-k1,1n';; esac
    for row in "${PROCESS_ROWS[@]}"; do
        [[ -z $FILTER || ${row,,} == *"${FILTER,,}"* ]] && printf '%s\n' "$row"
    done | sort -t '|' "$order" -k1,1n
}
process_lines() {
    local limit=${1:-0} n=0 pid state cpu rss name ram text
    add '     PID  S    CPU%         RSS  NAME'
    while IFS='|' read -r pid state cpu rss name; do
        [[ -n $pid ]] || continue
        human "$rss"; ram=$REPLY
        printf -v text '%8s  %1s  %6s  %10s  %s' "$pid" "$state" "${cpu/null/N\/A}" "$ram" "$name"; add "$text"
        ((n+=1)); ((limit > 0 && n >= limit)) && break
    done < <(sorted_processes)
    ((n > 0)) || add 'No readable processes match the filter.'
}
page_lines() {
    local page=$1 row name pct wait state rx tx _rxt _txt errors drops total used avail inode mount rr wr busy queue value text a b c
    LINES=()
    case $page in
        0)
            add "$OS | $ARCH | $ENVIRONMENT"
            add "Uptime: $((UPTIME/86400))d $((UPTIME/3600%24))h $((UPTIME/60%60))m  |  Load: $LOAD  |  CPUs: $CORES"
            heading 'RESOURCE PULSE'
            bar "$CPU_PCT"; add "CPU   $REPLY    I/O wait: ${CPU_WAIT/null/N\/A}%"
            bar "$MEM_PCT"; human "$MEM_USED"; a=$REPLY; human "$MEM_TOTAL"; b=$REPLY
            bar "$MEM_PCT"; add "RAM   $REPLY    $a / $b"
            bar "$SWAP_PCT"; add "SWAP  $REPLY"
            spark 100 "${CPU_HISTORY[@]}"; add "CPU history |$REPLY|"
            spark 100 "${MEM_HISTORY[@]}"; add "RAM history |$REPLY|"
            human "$NET_RX"; a=$REPLY; human "$NET_TX"; add "Network   RX $a/s   TX $REPLY/s (all non-loopback interfaces)"
            human "$DISK_READ"; a=$REPLY; human "$DISK_WRITE"; add "Block I/O R  $a/s   W  $REPLY/s (devices may overlap)"
            heading 'ACTIVE ALERTS'
            if ((!ALERTS_ENABLED)); then add 'Threshold alerts disabled.'
            elif ((${#ALERT_ROWS[@]})); then for row in "${ALERT_ROWS[@]}"; do add "! $row"; done
            else add 'No resource thresholds exceeded. Unavailable checks remain unknown.'; fi
            heading "TOP PROCESSES | $PROCESS_COUNT visible | $ZOMBIES zombies"
            process_lines 5 ;;
        1)
            add "$CPU_MODEL"
            add "Logical CPUs: $CORES | Load (1/5/15 min): $LOAD"
            for row in "${CPU_ROWS[@]}"; do
                IFS='|' read -r name pct wait <<< "$row"; bar "$pct"; printf -v text '%-7s %s  wait %s%%' "$name" "$REPLY" "${wait/null/N\/A}"; add "$text"
            done
            heading 'MEMORY'
            for row in "Total|$MEM_TOTAL" "Used|$MEM_USED" "Available|$MEM_AVAILABLE" "Cache + reclaimable|$MEM_CACHED" "Swap total|$SWAP_TOTAL" "Swap used|$SWAP_USED"; do
                IFS='|' read -r name value <<< "$row"; human "$value"; printf -v text '%-22s %s' "$name" "$REPLY"; add "$text"
            done
            heading 'PRESSURE STALLS (avg10 / avg60 / avg300 in %)'
            if [[ -n $PRESSURE ]]; then while IFS= read -r row; do [[ -n $row ]] && add "$row"; done <<< "$PRESSURE"; else add 'Not exposed by this kernel.'; fi
            heading 'TEMPERATURES'
            for row in "${SENSOR_ROWS[@]}"; do IFS='|' read -r name value <<< "$row"; add "$name: $((value/1000)) C"; done
            ((${#SENSOR_ROWS[@]})) || add 'No readable hwmon/thermal sensors.' ;;
        2)
            add 'LOCAL FILESYSTEMS (capacity and inode readings refresh every 15s)'
            add 'USED%  INODE%        USED       AVAIL       TOTAL  MOUNT / DEVICE'
            for row in "${FS_ROWS[@]}"; do
                IFS='|' read -r name total used avail pct inode mount <<< "$row"
                human "$used"; a=$REPLY; human "$avail"; b=$REPLY; human "$total"; c=$REPLY
                printf -v text '%5s  %6s  %10s  %10s  %10s  %s (%s)' "${pct/null/N\/A}" "${inode/null/N\/A}" "$a" "$b" "$c" "$mount" "$name"; add "$text"
            done
            heading 'BLOCK DEVICE I/O'
            add 'DEVICE            READ/s      WRITE/s  BUSY%  INFLIGHT'
            for row in "${IO_ROWS[@]}"; do
                IFS='|' read -r name rr wr busy queue <<< "$row"; human "$rr"; a=$REPLY; human "$wr"; b=$REPLY
                printf -v text '%-14s %11s  %11s  %5s  %8s' "$name" "$a" "$b" "${busy/null/N\/A}" "$queue"; add "$text"
            done
            ((${#IO_ROWS[@]})) || add 'No block-device counters are exposed.'
            add 'Busy% is time with outstanding I/O, not a measure of device saturation.'
            add 'Stacked devices can count the same I/O more than once.'
            spark 0 "${IO_HISTORY[@]}"; add "I/O trend (relative) |$REPLY|" ;;
        3)
            add 'INTERFACE       STATE           RX/s         TX/s    ERRORS     DROPS'
            for row in "${NET_ROWS[@]}"; do
                IFS='|' read -r name state rx tx _rxt _txt errors drops <<< "$row"
                human "$rx"; a=$REPLY; human "$tx"; b=$REPLY
                printf -v text '%-15s %-9s %12s %12s %9s %9s' "$name" "$state" "$a" "$b" "$errors" "$drops"; add "$text"
            done
            add 'Errors/drops are cumulative kernel counters. Bridges/veth can overlap.'
            spark 0 "${NET_HISTORY[@]}"; add "Network trend (relative) |$REPLY|"
            heading 'ADDRESSES'; for row in "${ADDRESS_ROWS[@]}"; do add "$row"; done
            heading 'LISTENING TCP / UDP SOCKETS (refresh every 30s)'
            for row in "${SOCKET_ROWS[@]}"; do add "$row"; done
            ((${#SOCKET_ROWS[@]})) || add 'No listening sockets reported.' ;;
        4)
            add "PROCESSES | $PROCESS_COUNT visible | $ZOMBIES zombies | sort: $SORT | filter: ${FILTER:-none}"
            add 'Sampled CPU: 100% = one logical CPU. New/reused PIDs show N/A initially.'
            add 'c CPU sort | m memory sort | p PID sort | / filter | j/k scroll'
            process_lines ;;
        5)
            add "INIT: $INIT | service/container details refresh every 30s | r refresh"
            heading 'SERVICES'
            for row in "${SERVICE_ROWS[@]}"; do IFS='|' read -r name state <<< "$row"; printf -v text '%-42s %s' "$name" "$state"; add "$text"; done
            heading 'CONTAINERS'; for row in "${CONTAINER_ROWS[@]}"; do add "$row"; done ;;
        6)
            add "Host          $HOST"; add "Distribution  $OS"; add "Kernel        $KERNEL"
            add "Architecture  $ARCH"; add "Environment   $ENVIRONMENT"; add "Init          $INIT"
            add "Packages      $PACKAGE_MANAGER (detection only; no package refresh)"
            heading 'CGROUP V2 (current group; ancestor limits may be tighter)'
            add "Memory        $CGROUP_MEMORY"; add "CPU           $CGROUP_CPU"
            add 'Main CPU/RAM gauges describe the visible host, not container quotas.'
            heading 'CAPABILITIES'
            add 'Core metrics: procfs + sysfs | no root required | no external services'
            for row in "${NOTES[@]}"; do add "$row"; done
            heading 'PASSIVE SECURITY'
            if ((SECURITY)); then for row in "${SECURITY_ROWS[@]}"; do add "$row"; done
            else add 'Use --security-scan to include local kernel policy observations.'; fi
            heading 'ABOUT'
            add "ServerInfoReport $VERSION by 0xPacman"
            add 'Read-only collectors. Files are written only when you request an export.' ;;
    esac
}

json_quote() {
    local value=$1 code char escape
    value=${value//\\/\\\\}; value=${value//\"/\\\"}
    if [[ $value == *[[:cntrl:]]* ]]; then
        for ((code=1; code<32; code++)); do
            printf -v char '\\%03o' "$code"; printf -v char '%b' "$char"
            printf -v escape '\\u%04x' "$code"; value=${value//"$char"/"$escape"}
        done
    fi
    printf '"%s"' "$value"
}
json_strings() {
    local item comma=
    printf '['
    for item in "$@"; do printf '%s' "$comma"; json_quote "$item"; comma=,; done
    printf ']'
}
json_rows() {
    local spec=$1 row comma='' field_comma i key value
    local -a keys values
    shift; IFS='|' read -r -a keys <<< "$spec"
    printf '['
    for row in "$@"; do
        printf '%s{' "$comma"; comma=,; field_comma=
        IFS='|' read -r -a values <<< "$row"
        for ((i=0; i<${#keys[@]}; i++)); do
            key=${keys[i]}; value=${values[i]:-null}; printf '%s' "$field_comma"; field_comma=,
            json_quote "${key%:n}"; printf ':'
            if [[ $key == *:n ]]; then
                if [[ $value =~ ^-?[0-9]+$ ]]; then printf '%s' "$value"; else printf null; fi
            else json_quote "$value"; fi
        done
        printf '}'
    done
    printf ']'
}
write_json() {
    printf '{"schema_version":1,"version":'; json_quote "$VERSION"
    printf ',"timestamp":'; json_quote "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf ',"sample":%s,"sample_ms":%s,"hostname":' "$SAMPLE" "$ELAPSED_MS"; json_quote "$HOST"
    printf ',"system":{"os":'; json_quote "$OS"; printf ',"kernel":'; json_quote "$KERNEL"
    printf ',"architecture":'; json_quote "$ARCH"; printf ',"environment":'; json_quote "$ENVIRONMENT"
    printf ',"init":'; json_quote "$INIT"; printf ',"package_manager":'; json_quote "$PACKAGE_MANAGER"
    printf ',"uptime_seconds":%s,"load_average":' "$UPTIME"; json_quote "$LOAD"; printf '}'
    printf ',"cpu":{"model":'; json_quote "$CPU_MODEL"
    printf ',"cores":%s,"usage_percent":%s,"iowait_percent":%s,"per_cpu":' "$CORES" "$CPU_PCT" "$CPU_WAIT"
    json_rows 'cpu|usage_percent:n|iowait_percent:n' "${CPU_ROWS[@]}"; printf '}'
    printf ',"memory":{"total_bytes":%s,"used_bytes":%s,"available_bytes":%s,"cached_bytes":%s,"usage_percent":%s,"swap_total_bytes":%s,"swap_used_bytes":%s,"swap_percent":%s}' "$MEM_TOTAL" "$MEM_USED" "$MEM_AVAILABLE" "$MEM_CACHED" "$MEM_PCT" "$SWAP_TOTAL" "$SWAP_USED" "$SWAP_PCT"
    printf ',"filesystems":'; json_rows 'device|total_bytes:n|used_bytes:n|available_bytes:n|usage_percent:n|inode_percent:n|mount' "${FS_ROWS[@]}"
    printf ',"disk_io":'; json_rows 'device|read_bytes_sec:n|write_bytes_sec:n|busy_percent:n|inflight:n' "${IO_ROWS[@]}"
    printf ',"network":'; json_rows 'interface|state|rx_bytes_sec:n|tx_bytes_sec:n|rx_bytes:n|tx_bytes:n|errors:n|drops:n' "${NET_ROWS[@]}"
    printf ',"processes":'; json_rows 'pid:n|state|cpu_percent:n|rss_bytes:n|name' "${PROCESS_ROWS[@]}"
    printf ',"services":'; json_rows 'name|state' "${SERVICE_ROWS[@]}"
    printf ',"temperatures":'; json_rows 'sensor|millidegrees_c:n' "${SENSOR_ROWS[@]}"
    printf ',"addresses":'; json_strings "${ADDRESS_ROWS[@]}"
    printf ',"listening_sockets":'; json_strings "${SOCKET_ROWS[@]}"
    printf ',"containers":'; json_strings "${CONTAINER_ROWS[@]}"
    printf ',"security":'; json_strings "${SECURITY_ROWS[@]}"
    printf ',"pressure":'; json_quote "$PRESSURE"
    printf ',"cgroup":{"memory":'; json_quote "$CGROUP_MEMORY"; printf ',"cpu":'; json_quote "$CGROUP_CPU"; printf '}'
    printf ',"notes":'; json_strings "${NOTES[@]}"
    printf ',"alerts":{"enabled":%s,"status":%s,"warnings":' "$([[ $ALERTS_ENABLED == 1 ]] && printf true || printf false)" "$STATUS"
    json_strings "${ALERT_ROWS[@]}"; printf '}}\n'
}
write_text() {
    local page line
    safe "$HOST"
    printf 'SERVERINFOREPORT %s | %s | %s\n' "$VERSION" "$REPLY" "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    printf 'Sample %s | interval %.2fs | status %s\n' "$SAMPLE" "$(awk -v n="$ELAPSED_MS" 'BEGIN {print n/1000}')" "$STATUS"
    for ((page=0; page<${#PAGES[@]}; page++)); do
        printf '\n=== %s ===\n' "${PAGES[page]}"; page_lines "$page"
        for line in "${LINES[@]}"; do safe "$line"; printf '%s\n' "$REPLY"; done
    done
}
write_report() {
    case $1 in
        json) write_json ;;
        txt) write_text ;;
        html)
            printf '%s\n' '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ServerInfoReport</title><style>body{background:#0b121b;color:#d4e1ef;font:14px/1.6 ui-monospace,monospace;margin:2rem}h1{color:#61d9ce}pre{white-space:pre-wrap;overflow-wrap:anywhere;border:1px solid #293949;padding:1.5rem;border-radius:10px}main{max-width:1200px;margin:auto}</style><main><h1>ServerInfoReport</h1><pre>'
            write_text | awk '{gsub(/&/, "\\&amp;");gsub(/</, "\\&lt;");gsub(/>/, "\\&gt;");print}'
            printf '%s\n' '</pre></main></html>' ;;
    esac
}
export_report() {
    local destination=$1 format=$2 parent temporary
    [[ ! -d $destination ]] || { MESSAGE='Export failed: destination is a directory'; return 2; }
    parent=${destination%/*}; [[ $parent != "$destination" ]] || parent=.
    [[ -n $parent ]] || parent=/
    temporary=$(umask 077; mktemp "$parent/.serverinfo.XXXXXX") || { MESSAGE='Export failed: cannot create temporary file'; return 2; }
    if (set -o pipefail; write_report "$format") > "$temporary" && mv -f -- "$temporary" "$destination"; then
        MESSAGE="Exported $format: $destination"; return 0
    fi
    rm -f -- "$temporary"; MESSAGE='Export failed: write or rename error'; return 2
}

terminal_size() {
    local size
    size=$(stty size <&9 2>/dev/null) || size='24 80'
    read -r ROWS COLS <<< "$size"
    uint "$ROWS" && ((ROWS > 0)) || ROWS=24
    uint "$COLS" && ((COLS > 0)) || COLS=80
}
terminal_cleanup() {
    if ((TERM_ACTIVE)); then
        # A signal may arrive while a collector has redirected stdin/stdout.
        # Keep terminal descriptors independent of those temporary redirections.
        stty "$SAVED_STTY" <&9 2>/dev/null || true
        printf '\033[0m\033[?25h\033[?1049l' >&8
        exec 9<&- 8>&-
        TERM_ACTIVE=0
    fi
}
# Theme and drawing code stays here in the deployed script. Only generated box
# glyphs bypass safe(); host/process data is always clipped and sanitized.
ui_color() {
    local role=$1 rgb=$2 indexed=$3 basic=$4 channel=38
    [[ $role == *bg ]] && channel=48
    if ((!COLOR)); then UI_COLORS[$role]=''
    elif ((UI_LEVEL == 24)); then printf -v "UI_COLORS[$role]" '\033[%s;2;%sm' "$channel" "$rgb"
    elif ((UI_LEVEL == 256)); then printf -v "UI_COLORS[$role]" '\033[%s;5;%sm' "$channel" "$indexed"
    else printf -v "UI_COLORS[$role]" '\033[%sm' "$basic"; fi
}
init_ui() {
    local role rgb indexed basic
    UI_LEVEL=16
    if [[ ${COLORTERM:-} == truecolor || ${COLORTERM:-} == 24bit ]]; then UI_LEVEL=24
    elif [[ ${TERM:-} == *256color* ]]; then UI_LEVEL=256; fi
    BOX_H='-'; BOX_V='|'; BOX_TL='+'; BOX_TR='+'; BOX_BL='+'; BOX_BR='+'
    GRAPH_CHARS=(' ' '.' ':' '-' '=' '+' '#' '%' '@')
    if ((!ASCII)) && [[ ${UI_LOCALE,,} == *utf*8* && ${TERM:-} != linux ]]; then
        BOX_H='─'; BOX_V='│'; BOX_TL='╭'; BOX_TR='╮'; BOX_BL='╰'; BOX_BR='╯'
        GRAPH_CHARS=(' ' '▁' '▂' '▃' '▄' '▅' '▆' '▇' '█')
    fi
    case $THEME in
        midnight)
            while read -r role rgb indexed basic; do ui_color "$role" "$rgb" "$indexed" "$basic"; done <<'PALETTE'
bg 11;18;27 233 40
text 215;227;242 253 37
dim 133;151;173 245 37
border 54;74;94 60 34
cpu 79;209;197 80 36
mem 180;159;235 147 35
net 100;181;246 75 34
disk 249;181;99 215 33
good 142;218;167 114 32
alert 255;198;109 222 33
bad 244;112;129 204 31
selectbg 79;209;197 80 46
selecttext 11;18;27 233 30
altbg 20;31;44 235 40
PALETTE
            ;;
        nord)
            while read -r role rgb indexed basic; do ui_color "$role" "$rgb" "$indexed" "$basic"; done <<'PALETTE'
bg 46;52;64 236 40
text 236;239;244 255 37
dim 163;176;193 248 37
border 76;86;106 60 34
cpu 136;192;208 110 36
mem 180;142;173 139 35
net 129;161;193 109 34
disk 235;203;139 222 33
good 163;190;140 150 32
alert 235;203;139 222 33
bad 191;97;106 131 31
selectbg 136;192;208 110 46
selecttext 46;52;64 236 30
altbg 59;66;82 237 40
PALETTE
            ;;
        light)
            while read -r role rgb indexed basic; do ui_color "$role" "$rgb" "$indexed" "$basic"; done <<'PALETTE'
bg 244;247;252 255 47
text 37;53;76 237 30
dim 88;106;127 242 30
border 153;172;195 249 34
cpu 20;125;117 30 36
mem 122;77;182 97 35
net 42;98;181 25 34
disk 156;99;17 136 33
good 31;120;70 28 32
alert 148;91;10 94 33
bad 180;42;61 124 31
selectbg 20;125;117 30 46
selecttext 244;247;252 255 30
altbg 226;233;243 254 47
PALETTE
            ;;
    esac
    UI_BASE=$'\033[0m'"${UI_COLORS[bg]}${UI_COLORS[text]}"
}
ui_style() {
    REPLY=$UI_BASE
    case $1 in
        title) REPLY+=${UI_COLORS[cpu]}$'\033[1m' ;;
        selected) REPLY+=${UI_COLORS[selectbg]}${UI_COLORS[selecttext]}$'\033[1m'; ((!COLOR)) && REPLY+=$'\033[7m' ;;
        table) REPLY+=${UI_COLORS[altbg]}$'\033[1m' ;;
        zebra) REPLY+=${UI_COLORS[altbg]} ;;
        normal) : ;;
        *) REPLY+=${UI_COLORS[$1]:-} ;;
    esac
    return 0
}
ui_text() {
    local y=$1 x=$2 width=$3 value=$4 style=${5:-normal} fragment
    ((y >= 1 && y <= ROWS && x >= 1 && x < COLS && width > 0)) || return 0
    ((width > COLS-x)) && width=$((COLS-x))
    safe "$value"; value=${REPLY:0:width}; ui_style "$style"
    printf -v fragment '\033[%s;%sH%s%-*s' "$y" "$x" "$REPLY" "$width" "$value"
    FRAME+=$fragment
}
ui_raw() {
    local y=$1 x=$2 value=$3 style=${4:-border} fragment
    ui_style "$style"
    printf -v fragment '\033[%s;%sH%s%s' "$y" "$x" "$REPLY" "$value"
    FRAME+=$fragment
}
ui_repeat() { printf -v REPLY '%*s' "$2" ''; REPLY=${REPLY// /$1}; }
ui_panel() {
    local y=$1 x=$2 width=$3 height=$4 title=$5 accent=${6:-title} edge i
    ui_repeat "$BOX_H" "$((width-2))"; edge=$REPLY
    ui_raw "$y" "$x" "$BOX_TL$edge$BOX_TR"
    for ((i=1;i<height-1;i++)); do
        ui_raw "$((y+i))" "$x" "$BOX_V"
        ui_raw "$((y+i))" "$((x+width-1))" "$BOX_V"
    done
    ui_raw "$((y+height-1))" "$x" "$BOX_BL$edge$BOX_BR"
    safe "$title"; title=${REPLY:0:$((width-8))}
    ui_text "$y" "$((x+2))" "$((${#title}+2))" " $title " "$accent"
}
ui_severity() {
    REPLY=$3
    if [[ $1 != null ]]; then
        if (($1 >= 95)); then REPLY=bad
        elif (($1 >= $2)); then REPLY=alert; fi
    fi
}
ui_meter() {
    local y=$1 x=$2 width=$3 pct=$4 style=$5 filled
    ui_repeat '.' "$width"; ui_raw "$y" "$x" "$REPLY" border
    [[ $pct != null ]] || return 0
    filled=$((pct*width/100)); ((filled > width)) && filled=$width
    ui_repeat "${GRAPH_CHARS[8]}" "$filled"; ui_raw "$y" "$x" "$REPLY" "$style"
}
ui_graph() {
    local y=$1 x=$2 width=$3 height=$4 maximum=$5 style=$6
    local i j count padding value units level line
    shift 6
    local -a values=("$@")
    count=${#values[@]}
    ((count > width)) && { values=("${values[@]:count-width}"); count=$width; }
    if ((maximum == 0)); then
        for value in "${values[@]}"; do [[ $value != null ]] && ((value > maximum)) && maximum=$value; done
    fi
    ((maximum > 0)) || maximum=1
    padding=$((width-count)); printf -v padding '%*s' "$padding" ''
    for ((i=0;i<height;i++)); do
        line=$padding
        for ((j=0;j<count;j++)); do
            value=${values[j]}
            if [[ $value == null ]]; then line+=' '; continue; fi
            units=$((value*height*8/maximum))
            ((value > 0 && units == 0)) && units=1
            level=$((units-(height-1-i)*8))
            ((level < 0)) && level=0; ((level > 8)) && level=8
            if ((value == 0 && i == height-1)); then line+='.'; else line+=${GRAPH_CHARS[level]}; fi
        done
        ui_raw "$((y+i))" "$x" "$line" "$style"
    done
}
ui_overview() {
    local width=$((COLS-3)) top=7 middle=5 bottom left right rx y h style a b value pid state cpu rss name n text
    ((ROWS >= 30)) && { top=9; middle=7; }
    left=$(((width-1)/2)); right=$((width-left-1)); rx=$((left+3))
    bottom=$((ROWS-7-top-middle)); y=5; h=$top
    ui_panel "$y" 2 "$left" "$h" 'CPU' cpu
    ui_severity "$CPU_PCT" "$CPU_LIMIT" cpu; style=$REPLY
    ui_text "$((y+1))" 4 "$((left-4))" "${CPU_PCT/null/N\/A}% utilization  /  $CORES logical CPUs" "$style"
    ui_meter "$((y+2))" 4 "$((left-4))" "$CPU_PCT" "$style"
    ui_graph "$((y+3))" 4 "$((left-4))" "$((h-6))" 100 cpu "${CPU_HISTORY[@]}"
    ui_text "$((y+h-3))" 4 "$((left-4))" "Load  $LOAD" dim
    ui_text "$((y+h-2))" 4 "$((left-4))" "I/O wait ${CPU_WAIT/null/N\/A}%   |   last ${#CPU_HISTORY[@]} samples" dim

    ui_panel "$y" "$rx" "$right" "$h" 'MEMORY' mem
    ui_severity "$MEM_PCT" "$MEM_LIMIT" mem; style=$REPLY
    human "$MEM_USED"; a=$REPLY; human "$MEM_TOTAL"; b=$REPLY
    ui_text "$((y+1))" "$((rx+2))" "$((right-4))" "${MEM_PCT/null/N\/A}% used  /  $a of $b" "$style"
    ui_meter "$((y+2))" "$((rx+2))" "$((right-4))" "$MEM_PCT" "$style"
    ui_graph "$((y+3))" "$((rx+2))" "$((right-4))" "$((h-6))" 100 mem "${MEM_HISTORY[@]}"
    human "$MEM_AVAILABLE"; ui_text "$((y+h-3))" "$((rx+2))" "$((right-4))" "Available  $REPLY" dim
    human "$SWAP_USED"; a=$REPLY; human "$SWAP_TOTAL"
    ui_text "$((y+h-2))" "$((rx+2))" "$((right-4))" "Swap  $a / $REPLY" dim

    y=$((5+top)); h=$middle
    ui_panel "$y" 2 "$left" "$h" 'NETWORK' net
    human "$NET_RX"; a=$REPLY; human "$NET_TX"; b=$REPLY
    ui_text "$((y+1))" 4 "$((left-4))" "RX $a/s   TX $b/s" net
    ui_graph "$((y+2))" 4 "$((left-4))" "$((h-4))" 0 net "${NET_HISTORY[@]}"
    ui_text "$((y+h-2))" 4 "$((left-4))" "${#NET_ROWS[@]} interfaces  |  trend auto-scaled" dim
    ui_panel "$y" "$rx" "$right" "$h" 'STORAGE I/O' disk
    human "$DISK_READ"; a=$REPLY; human "$DISK_WRITE"; b=$REPLY
    ui_text "$((y+1))" "$((rx+2))" "$((right-4))" "R $a/s   W $b/s" disk
    ui_graph "$((y+2))" "$((rx+2))" "$((right-4))" "$((h-4))" 0 disk "${IO_HISTORY[@]}"
    ui_text "$((y+h-2))" "$((rx+2))" "$((right-4))" "Devices: ${#IO_ROWS[@]} | I/O may overlap" dim

    y=$((y+middle)); left=$((width*3/5)); right=$((width-left-1)); rx=$((left+3))
    ui_panel "$y" 2 "$left" "$bottom" "PROCESSES / $SORT" title
    ui_text "$((y+1))" 4 "$((left-4))" '   PID   CPU%        RSS  NAME' table
    n=0
    while IFS='|' read -r pid state cpu rss name; do
        [[ -n $pid ]] || continue
        human "$rss"; printf -v text '%6s %6s %10s  %s' "$pid" "${cpu/null/N\/A}" "$REPLY" "$name"
        style=normal; ((n%2 == 0)) && style=zebra
        ui_text "$((y+2+n))" 4 "$((left-4))" "$text" "$style"
        ((n+=1)); ((n >= bottom-3)) && break
    done < <(sorted_processes)
    ui_panel "$y" "$rx" "$right" "$bottom" 'HEALTH' good
    if ((!ALERTS_ENABLED)); then text='ALERTS DISABLED'; style=dim
    elif ((${#ALERT_ROWS[@]})); then text="WARN / ${#ALERT_ROWS[@]} active"; style=alert
    else text='OK / within thresholds'; style=good; fi
    ui_text "$((y+1))" "$((rx+2))" "$((right-4))" "$text" "$style"
    if ((${#ALERT_ROWS[@]})); then
        for ((n=0;n<${#ALERT_ROWS[@]} && n<bottom-3;n++)); do
            ui_text "$((y+2+n))" "$((rx+2))" "$((right-4))" "! ${ALERT_ROWS[n]}" alert
        done
    else
        ui_text "$((y+2))" "$((rx+2))" "$((right-4))" "$PROCESS_COUNT processes / $ZOMBIES zombies" dim
        ((bottom > 5)) && ui_text "$((y+3))" "$((rx+2))" "$((right-4))" 'Unavailable checks stay unknown.' dim
        ((bottom > 6)) && ui_text "$((y+4))" "$((rx+2))" "$((right-4))" 'CPU / memory: visible host scope.' dim
    fi
    SCROLL=0
}
ui_detail() {
    local body=$((ROWS-9)) i line style title=${PAGES[PAGE]} thumb
    if ((HELP)); then
        title=KEYBOARD
        LINES=('NAVIGATION' '1..7          Open a view' 'Tab / arrows  Previous / next view' 'j/k, up/down  Scroll one line' 'PgUp/PgDn     Scroll one screen' 'Home/End      First / last line' '' 'CONTROLS' 'Space         Pause / resume sampling' 'c / m / p     Sort processes by CPU / RSS / PID' '/             Filter processes (empty clears)' 'r             Refresh details on the next sample' 'e             Export snapshot as JSON' 't             Cycle midnight / nord / light theme' '?             Toggle help' 'q / Esc       Quit' '' 'Unknown readings appear as N/A; JSON uses null.' 'Use --ascii for plain borders and graphs.' 'Use --no-color for a monochrome terminal.')
    else page_lines "$PAGE"; fi
    ((SCROLL > ${#LINES[@]}-body)) && SCROLL=$((${#LINES[@]}-body))
    ((SCROLL < 0)) && SCROLL=0
    ui_panel 5 2 "$((COLS-3))" "$((ROWS-7))" "$title" title
    for ((i=0;i<body;i++)); do
        line=${LINES[i+SCROLL]:-}; style=normal
        if [[ $line == '-- '* || $line == NAVIGATION || $line == CONTROLS ]]; then style=title
        elif [[ $line == '! '* ]]; then style=alert
        elif [[ $line == *'CPU%'* || $line == USED%* || $line == INTERFACE* || $line == DEVICE* ]]; then style=table
        elif [[ $line == cpu*'['* || $line == CPU*'['* ]]; then style=cpu
        elif [[ $line == RAM* || $line == SWAP* ]]; then style=mem
        elif [[ $line == *unavailable* || $line == *'N/A'* || $line == *'Use --'* ]]; then style=dim
        elif ((i%2)); then style=zebra; fi
        ui_text "$((i+6))" 4 "$((COLS-7))" "$line" "$style"
    done
    if ((${#LINES[@]} > body)); then
        thumb=$((6+SCROLL*(body-1)/(${#LINES[@]}-body)))
        ui_raw "$thumb" "$((COLS-2))" "${GRAPH_CHARS[8]}" cpu
    fi
    ui_text "$((ROWS-2))" 2 "$((COLS-3))" " Lines $((SCROLL+1)) / ${#LINES[@]}   |   j/k scroll   |   theme: $THEME" dim
}
draw_at() {
    FRAME=''; ui_text "$1" 1 "$((COLS-1))" "$2" "${3:-normal}"
    printf '%s%s' "$FRAME" "$UI_BASE"
}
draw_screen() {
    local i x width label state=LIVE style=good detail fragment
    local -a labels=('1 Home' '2 CPU' '3 Disk' '4 Net' '5 Proc' '6 Svc' '7 Sys')
    terminal_size; FRAME=''
    if ((ROWS < 12 || COLS < 55)); then
        printf '\033[H\033[J'
        draw_at 1 'ServerInfoReport: resize to at least 55 columns x 12 rows.' title
        draw_at 2 'Press q to quit.'; return
    fi
    # Clear rows in the frame buffer, including the reserved final column after
    # a resize. Flush once; do not clear the whole screen between updates.
    FRAME=$UI_BASE
    for ((i=1;i<=ROWS;i++)); do
        printf -v fragment '\033[%s;1H\033[2K' "$i"; FRAME+=$fragment
    done
    ((PAUSED)) && { state=PAUSED; style=alert; }
    ui_text 1 2 22 'SERVER / INFO REPORT' title
    detail="$state  ${INTERVAL}s  sample $SAMPLE"
    ui_text 1 "$((COLS-${#detail}-1))" "${#detail}" "$detail" "$style"
    ui_text 2 2 "$((COLS-3))" "$HOST  /  $OS  /  up $((UPTIME/86400))d $((UPTIME/3600%24))h $((UPTIME/60%60))m" dim
    x=2
    for ((i=0;i<7;i++)); do
        label=${labels[i]}
        ((COLS >= 110)) && label="$((i+1)) ${PAGES[i]}"
        ((COLS < 75)) && label="$((i+1)) ${PAGES[i]:0:2}"
        width=$((${#label}+2)); style=dim; ((i == PAGE && !HELP)) && style=selected
        ui_text 3 "$x" "$width" " $label " "$style"; x=$((x+width+1))
    done
    ui_text 4 2 "$((COLS-3))" "${PAGES[PAGE]}  /  ${#ALERT_ROWS[@]} warnings  /  t theme  /  ? help" dim
    if ((PAGE == 0 && !HELP && COLS >= 80 && ROWS >= 24)); then
        ui_overview
        ui_text "$((ROWS-2))" 2 "$((COLS-3))" " Read-only  |  CPU/RAM host scope  |  theme: $THEME" dim
    else ui_detail; fi
    ui_text "$((ROWS-1))" 2 "$((COLS-3))" "${MESSAGE:-Space pause  /  e export JSON  /  r refresh details}" dim
    ui_text "$ROWS" 2 "$((COLS-3))" ' q quit   1-7 views   j/k scroll   c/m/p sort   / filter   t theme' table
    printf '%s%s' "$FRAME" "$UI_BASE"
}
filter_prompt() {
    local input=$FILTER key
    while :; do
        draw_at "$((ROWS-1))" " Filter: ${input}_ (Enter apply, Esc cancel)" title
        IFS= read -rsn1 key || return
        case $key in
            '') FILTER=$input; SCROLL=0; return ;;
            $'\033') return ;;
            $'\177'|$'\b') input=${input%?} ;;
            *) [[ $key == [[:print:]] && ${#input} -lt 100 ]] && input+=$key ;;
        esac
    done
}
handle_key() {
    local key=$1 suffix='' filename
    if [[ $key == $'\033' ]]; then
        IFS= read -rsn1 -t 0.05 suffix || return 10
        if [[ $suffix == '[' ]]; then
            IFS= read -rsn1 -t 0.05 suffix || return 0
            case $suffix in
                A) key=k;; B) key=j;; C) key=']';; D) key='[';; H) key=g;; F) key=G;;
                5|6) key=$suffix; IFS= read -rsn1 -t 0.05 suffix || true; key="page$key";;
                *) return 0;;
            esac
        else return 0; fi
    fi
    case $key in
        q|Q) return 10 ;;
        [1-7]) PAGE=$((key-1)); SCROLL=0; HELP=0 ;;
        $'\t'|']') PAGE=$(((PAGE+1)%7)); SCROLL=0; HELP=0 ;;
        '[') PAGE=$(((PAGE+6)%7)); SCROLL=0; HELP=0 ;;
        j) ((SCROLL+=1));; k) ((SCROLL-=1));;
        page5) ((SCROLL-=ROWS-9));; page6) ((SCROLL+=ROWS-9));;
        g) SCROLL=0;; G) SCROLL=${#LINES[@]};;
        ' ') PAUSED=$((1-PAUSED)); MESSAGE= ;;
        c) SORT=cpu; SCROLL=0;; m) SORT=mem; SCROLL=0;; p) SORT=pid; SCROLL=0;;
        /) PAGE=4; HELP=0; filter_prompt ;;
        r) LAST_SLOW=-1; LAST_DETAIL=-1; MESSAGE='Details will refresh on the next sample' ;;
        e) filename=${OUTPUT:-serverinfo-$(date -u '+%Y%m%dT%H%M%SZ')-$$.json}; export_report "$filename" json || true ;;
        t) case $THEME in midnight) THEME=nord;; nord) THEME=light;; *) THEME=midnight;; esac; init_ui ;;
        '?') HELP=$((1-HELP)); SCROLL=0 ;;
    esac
    return 0
}
run_tui() {
    local key result deadline
    exec 9<&0 8>&1
    SAVED_STTY=$(stty -g <&9) || { exec 9<&- 8>&-; fail 'cannot read terminal settings'; return 2; }
    TERM_ACTIVE=1
    trap terminal_cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    trap 'REDRAW=1' WINCH
    stty -echo -icanon min 1 time 0
    init_ui
    printf '\033[?1049h\033[?25l\033[H\033[J'
    collect_fast || return 2
    MESSAGE='Sampling counters...'; draw_screen; REDRAW=0
    deadline=$((SECONDS+INTERVAL))
    while :; do
        if ((!PAUSED && SECONDS >= deadline)); then
            collect_snapshot || return 2
            deadline=$((SECONDS+INTERVAL)); MESSAGE=
            REDRAW=1
            ((COUNT > 0 && SAMPLE >= COUNT)) && break
        fi
        key=
        if IFS= read -rsn1 -t 0.2 key; then
            handle_key "$key"; result=$?
            ((result == 10)) && break
            REDRAW=1
        fi
        if ((REDRAW)); then draw_screen; REDRAW=0; fi
    done
    terminal_cleanup
    trap - EXIT INT TERM HUP WINCH
    return "$STATUS"
}
main() {
    local result command
    parse_args "$@"; result=$?
    ((result == 10)) && return 0
    ((result == 0)) || return "$result"
    [[ $(uname -s) == Linux ]] || { fail 'Linux is required; use WSL on Windows'; return 2; }
    for command in awk sort df date sleep uname; do
        has "$command" || { fail "required utility is missing: $command"; return 2; }
    done
    [[ -r $PROC/stat && -r $PROC/meminfo && -r $PROC/uptime ]] || { fail 'mount procfs before running'; return 2; }
    if [[ $MODE == auto ]]; then
        if [[ -t 0 && -t 1 && ${TERM:-dumb} != dumb ]]; then MODE=tui; else MODE=report; fi
    fi
    if [[ $MODE == tui ]]; then
        [[ -t 0 && -t 1 && ${TERM:-dumb} != dumb ]] || { fail 'TUI needs an interactive terminal; use --report or --watch'; return 2; }
        has stty || { fail 'TUI requires stty'; return 2; }
    fi
    if [[ -n $OUTPUT || $MODE == tui ]]; then
        for command in mktemp mv rm; do has "$command" || { fail "exports require $command"; return 2; }; done
    fi
    detect_system
    if [[ $MODE == tui ]]; then run_tui; return $?; fi
    collect_fast || return 2
    while :; do
        sleep "$INTERVAL"
        collect_snapshot || return 2
        if [[ -n $OUTPUT ]]; then
            export_report "$OUTPUT" "$FORMAT" || { fail "$MESSAGE"; return 2; }
        fi
        if ((QUIET)); then printf 'status=%s warnings=%s\n' "$STATUS" "${#ALERT_ROWS[@]}"
        elif [[ -z $OUTPUT ]]; then write_report "$FORMAT" || return 2
        else printf '%s\n' "$MESSAGE" >&2; fi
        [[ $MODE != watch ]] && break
        ((COUNT > 0 && SAMPLE >= COUNT)) && break
    done
    return "$STATUS"
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
