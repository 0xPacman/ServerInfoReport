#!/bin/bash

# Advanced Server Information Report Tool
# Version: 3.1 - Standalone Edition
# Author: 0xPacman
# License: MIT

# Version variable (used by --version)
VERSION="3.1"

# Color definitions and formatting (can be disabled with --no-color or when not a TTY)
NC="\033[0m"  
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
BOLD="\033[1m"
DIM="\033[2m"
UNDERLINE="\033[4m"
ENABLE_COLOR=true

# Configuration variables (embedded in script - no external config file needed)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)"

# Handle cases where script is run via curl/wget pipe (no real file path)
if [[ "${BASH_SOURCE[0]}" == *"/proc/self/fd/"* ]] || [[ "${BASH_SOURCE[0]}" == "/dev/stdin" ]] || [[ ! -d "$SCRIPT_DIR" ]]; then
    SCRIPT_DIR="$(pwd)"
fi

LOG_FILE="${SCRIPT_DIR}/server_report.log"
ENABLE_LOGGING=true
ENABLE_ALERTS=true
ENABLE_EXPORT=false
ALERT_THRESHOLD_CPU=80
ALERT_THRESHOLD_MEM=85
ALERT_THRESHOLD_DISK=90
DETAILED_MODE=false
QUIET_MODE=false
EXPORT_FORMAT="txt"
OUTPUT_FILE=""
MONITOR_INTERVAL=30
CUSTOM_SERVICES=""  # Comma separated list via --services
FORCED_EXIT_CODE=0  # Will be computed based on warnings/errors

# Global variables
TOTAL_WARNINGS=0
TOTAL_ERRORS=0
REPORT_START_TIME=$(date +%s)

# Utility functions
rotate_logs() {
    # Simple log rotation if file >1MB
    if [ -f "$LOG_FILE" ]; then
        local size
        size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt 1048576 ]; then
            mv "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
            : > "$LOG_FILE" 2>/dev/null || true
        fi
    fi
}

log_message() {
    local message="$1"
    local level="${2:-INFO}"
    if [ "$ENABLE_LOGGING" = true ]; then
        # Ensure log directory writable; fallback to /tmp
        if ! touch "$LOG_FILE" 2>/dev/null; then
            LOG_FILE="/tmp/server_report.log"
            touch "$LOG_FILE" 2>/dev/null || ENABLE_LOGGING=false
        fi
        rotate_logs
        if [ "$ENABLE_LOGGING" = true ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
        fi
    fi
}

disable_colors() {
    NC=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; BOLD=""; DIM=""; UNDERLINE=""; ENABLE_COLOR=false
}

show_help() {
    cat << EOF
${BOLD}Advanced Server Information Report Tool - Standalone Edition${NC}

${UNDERLINE}Usage:${NC}
    $(basename "$0") [OPTIONS]

${UNDERLINE}Options:${NC}
    -h, --help          Show this help message
    -d, --detailed      Enable detailed mode with additional information
    -q, --quiet         Run in quiet mode (minimal output)
    -o, --output FILE   Export report to specified file
    -f, --format FORMAT Export format (txt, json, html) [default: txt]
    --no-log           Disable logging
    --no-alerts        Disable alert checking
    --cpu-threshold N  Set CPU alert threshold (default: 80%)
    --mem-threshold N  Set memory alert threshold (default: 85%)
    --disk-threshold N Set disk alert threshold (default: 90%)
    --monitor          Run in continuous monitoring mode
    --interval N       Interval seconds for --monitor (default 30)
    --no-color         Disable colored output
    --security-scan    Run comprehensive security scan
    --performance-test Run performance benchmarks
    --health-check     Run system health check
    --services list    Comma separated service names for health checks
    --version          Show version and exit

${UNDERLINE}Examples:${NC}
    $(basename "$0") -d -o report.html -f html
    $(basename "$0") --monitor --cpu-threshold 90
    $(basename "$0") -q -o status.json -f json
    $(basename "$0") --security-scan --detailed
    $(basename "$0") --health-check

EOF
}

check_threshold() {
    local value="$1"
    local threshold="$2"
    local metric="$3"
    
    # Check if value is empty or not a number
    if [ -z "$value" ] || [ "$value" = "" ]; then
        return 0
    fi
    
    # Use bc for comparison if available, otherwise use basic arithmetic
    local is_above_threshold=0
    if command -v bc &>/dev/null; then
        is_above_threshold=$(echo "$value > $threshold" | bc -l 2>/dev/null || echo "0")
    else
        # Fallback to integer comparison
        local value_int=${value%.*}
        local threshold_int=${threshold%.*}
        if [ -n "$value_int" ] && [ -n "$threshold_int" ] && [ "$value_int" -gt "$threshold_int" ]; then
            is_above_threshold=1
        fi
    fi
    
    if [ "$is_above_threshold" -eq 1 ]; then
        ((TOTAL_WARNINGS++))
        log_message "WARNING: $metric is above threshold ($value% > $threshold%)" "WARN"
        return 1
    fi
    return 0
}

parse_cpu_percentage() {
    local cpu_string="$1"
    echo "$cpu_string" | grep -oE '[0-9]+\.?[0-9]*' | head -1
}

extract_number() { # generic helper
    echo "$1" | grep -oE '[0-9]+' | head -1
}

get_os() {
    case "$(uname -s)" in
        Linux*)   echo "Linux" ;;
        Darwin*)  echo "Mac" ;;
        *)        echo "Other" ;;
    esac
}

draw_line() {
    printf '%*s\n' "${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}" '' | tr ' ' -
}

get_cpu_usage() {
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then
        if [ -r /proc/stat ]; then
            local cpu1 idle1 total1 cpu2 idle2 total2
            read -r cpu user nice system idle iowait irq softirq steal guest < /proc/stat
            idle1=$idle; total1=$((user+nice+system+idle+iowait+irq+softirq+steal))
            sleep 0.5
            read -r cpu user nice system idle iowait irq softirq steal guest < /proc/stat
            idle2=$idle; total2=$((user+nice+system+idle+iowait+irq+softirq+steal))
            local diff_idle=$((idle2-idle1))
            local diff_total=$((total2-total1))
            if [ "$diff_total" -gt 0 ]; then
                local usage=$(echo "scale=1; (1-($diff_idle/$diff_total))*100" | bc -l 2>/dev/null || echo 0)
                echo "$usage"
                return
            fi
        fi
        # fallback
        if command -v top &>/dev/null; then
            local cpu_output=$(top -bn1 | grep "Cpu(s)" | awk '{for(i=1;i<=NF;i++) if($i ~ /id,/) id=$i} END {gsub(/id,/,"",id); if(id!="") printf "%.1f", 100-id;}' )
            echo "${cpu_output:-0.0}"
        else
            echo "0.0"
        fi
    elif [ "$os" == "Mac" ]; then
        local mac_cpu=$(top -l 1 | grep "CPU usage" | awk -F'idle' '{print $1}' | awk '{print $3}' | sed 's/%//' 2>/dev/null)
        echo "${mac_cpu:-0.0}"
    else
        echo "0.0"
    fi
}

get_cpu_count() {
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then
        nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "1"
    elif [ "$os" == "Mac" ]; then
        sysctl -n hw.ncpu 2>/dev/null || echo "1"
    else
        echo "1"
    fi
}

get_memory_usage() {
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then
        if command -v free &>/dev/null; then
            free -m | awk 'NR==2 {printf "Total: %s MB | Used: %s MB | Free: %s MB | Available: %s MB", $2,$3,$4,$7}'
        elif [ -f /proc/meminfo ]; then
            local total=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
            local available=$(grep MemAvailable /proc/meminfo | awk '{print int($2/1024)}' 2>/dev/null || echo "0")
            local used=$((total - available))
            echo "Total: ${total} MB | Used: ${used} MB | Available: ${available} MB"
        else
            echo "Memory info not available"
        fi
    elif [ "$os" == "Mac" ]; then
        top -l 1 | grep "PhysMem" | sed 's/^[ \t]*//' 2>/dev/null || echo "Memory info not available"
    else
        echo "Memory info not available"
    fi
}

get_storage_usage() {
    if command -v df &>/dev/null; then
        df -h / 2>/dev/null
    else
        echo "Storage info not available"
    fi
}

detect_environment() {
    local envs=()
    # Container / Docker
    if [ -f /.dockerenv ] || grep -qa 'docker' /proc/1/cgroup 2>/dev/null; then
        envs+=("Docker")
    fi
    # WSL
    if grep -qi 'microsoft' /proc/version 2>/dev/null; then
        envs+=("WSL")
    fi
    # Virtualization
    if command -v systemd-detect-virt &>/dev/null; then
        local virt=$(systemd-detect-virt 2>/dev/null)
        if [ -n "$virt" ] && [ "$virt" != "none" ]; then
            envs+=("Virt:$virt")
        fi
    fi
    if [ ${#envs[@]} -eq 0 ]; then
        echo "BareMetal"
    else
        IFS=','; echo "${envs[*]}"; unset IFS
    fi
}

escape_json() {
    # Escape backslashes, quotes, and newlines
    echo "$1" | sed 's/\\/\\\\/g; s/\"/\\\"/g; s/\n/\\n/g'
}

html_safe() {
    local s="$1"
    s=${s//&/&amp;}
    s=${s//</&lt;}
    s=${s//>/&gt;}
    s=${s//\"/&quot;}
    echo "$s"
}

get_uptime_info() {
    local os=$(get_os)
    if command -v uptime &>/dev/null; then
        if [ "$os" == "Linux" ]; then
            uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}'
        elif [ "$os" == "Mac" ]; then
            uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}'
        else
            uptime
        fi
    else
        echo "Uptime info not available"
    fi
}

get_load_average() {
    local os=$(get_os)
    if command -v uptime &>/dev/null; then
        if [ "$os" == "Linux" ] || [ "$os" == "Mac" ]; then
            uptime | awk -F'load average: ' '{print $2}' 2>/dev/null || uptime | awk -F'load averages: ' '{print $2}' 2>/dev/null || echo "N/A"
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

get_cpu_temperature() {
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then
        # Try different methods to get CPU temperature
        if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
            local temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
            if [ -n "$temp" ] && [ "$temp" -gt 0 ]; then
                echo "$(($temp / 1000))°C"
                return
            fi
        fi
        
        # Try sensors command
        if command -v sensors &>/dev/null; then
            local temp_output=$(sensors 2>/dev/null | grep -E "Core 0|Package id 0" | head -1 | grep -oE '\+[0-9]+\.[0-9]+°C')
            if [ -n "$temp_output" ]; then
                echo "$temp_output"
                return
            fi
        fi
        
        echo "N/A"
    else
        echo "N/A"
    fi
}

get_ip_info() {
    local os=$(get_os)
    if [ "$os" == "Linux" ] || [ "$os" == "Mac" ]; then
        # Get primary IP address
        if command -v ip &>/dev/null; then
            ip route get 8.8.8.8 2>/dev/null | awk 'NR==1 {print $7}' | head -1
        elif command -v ifconfig &>/dev/null; then
            ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1 | sed 's/addr://'
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

get_memory_percentage() {
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then
        if command -v free &>/dev/null; then
            free | awk 'NR==2{printf "%.1f", $3*100/$2}'
        elif [ -f /proc/meminfo ]; then
            local total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
            local available=$(grep MemAvailable /proc/meminfo | awk '{print $2}' 2>/dev/null || echo "0")
            local used=$((total - available))
            echo "scale=1; $used * 100 / $total" | bc -l 2>/dev/null || echo "0"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

get_disk_percentage() {
    if command -v df &>/dev/null; then
        df / 2>/dev/null | awk 'NR==2{print $5}' | sed 's/%//' || echo "0"
    else
        echo "0"
    fi
}

check_disk_health() {
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then
        if command -v smartctl &>/dev/null; then
            echo -e "${BLUE}${BOLD}SMART Disk Health:${NC}"
            for disk in $(lsblk -d -n -o name 2>/dev/null | grep -E '^sd|^nvme' | head -5); do
                local health=$(smartctl -H /dev/$disk 2>/dev/null | grep "SMART overall-health" | awk '{print $6}')
                if [ "$health" == "PASSED" ]; then
                    echo -e "${GREEN}/dev/$disk: $health${NC}"
                elif [ -n "$health" ]; then
                    echo -e "${RED}/dev/$disk: $health${NC}"
                    ((TOTAL_WARNINGS++))
                fi
            done
        else
            echo -e "${YELLOW}smartctl not available for disk health check${NC}"
        fi
    fi
}

get_process_info() {
    echo -e "${BLUE}${BOLD}Top 5 CPU-consuming processes:${NC}"
    if command -v ps &>/dev/null; then
        ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5 | awk '{printf "%-12s %-8s %-8s %s\n", $1, $2, $3"%", $11}' || echo "Process info not available"
    else
        echo "Process info not available"
    fi
    
    echo -e "\n${BLUE}${BOLD}Top 5 Memory-consuming processes:${NC}"
    if command -v ps &>/dev/null; then
        ps aux --sort=-%mem 2>/dev/null | head -6 | tail -5 | awk '{printf "%-12s %-8s %-8s %s\n", $1, $2, $4"%", $11}' || echo "Process info not available"
    else
        echo "Process info not available"
    fi
}

check_service() {
    local service="$1"
    if command -v systemctl &>/dev/null; then
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "${GREEN}✓ $service is running${NC}"
        elif systemctl list-unit-files 2>/dev/null | grep -q "^$service"; then
            echo -e "${RED}✗ $service is not running${NC}"
            ((TOTAL_WARNINGS++))
        else
            echo -e "${YELLOW}? $service not found${NC}"
        fi
    elif command -v service &>/dev/null; then
        if service "$service" status &>/dev/null; then
            echo -e "${GREEN}✓ $service is running${NC}"
        else
            echo -e "${RED}✗ $service status unknown${NC}"
        fi
    else
        echo -e "${YELLOW}systemctl/service not available${NC}"
    fi
}

check_network_services() {
    echo -e "${BLUE}${BOLD}Network Services:${NC}"
    
    # Check SSH
    if command -v ss &>/dev/null; then
        if ss -tuln | grep -q ":22 "; then
            echo -e "${GREEN}✓ SSH service is listening${NC}"
        else
            echo -e "${YELLOW}⚠ SSH service not detected${NC}"
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tuln 2>/dev/null | grep -q ":22 "; then
            echo -e "${GREEN}✓ SSH service is listening${NC}"
        else
            echo -e "${YELLOW}⚠ SSH service not detected${NC}"
        fi
    else
        echo -e "${YELLOW}Network tools not available${NC}"
    fi
    
    # Check HTTP services
    local http_ports="80 443 8080 8443"
    for port in $http_ports; do
        if command -v ss &>/dev/null; then
            if ss -tuln | grep -q ":$port "; then
                echo -e "${GREEN}✓ HTTP service on port $port${NC}"
            fi
        elif command -v netstat &>/dev/null; then
            if netstat -tuln 2>/dev/null | grep -q ":$port "; then
                echo -e "${GREEN}✓ HTTP service on port $port${NC}"
            fi
        fi
    done
}

check_docker_containers() {
    if command -v docker &>/dev/null; then
        echo -e "${BLUE}${BOLD}Docker Containers:${NC}"
        local running=$(docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | tail -n +2 | wc -l)
        local total=$(docker ps -a --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | tail -n +2 | wc -l)
        echo -e "${CYAN}Running: $running | Total: $total${NC}"
        
        if [ "$DETAILED_MODE" = true ] && [ "$running" -gt 0 ]; then
            docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
        fi
    fi
}

check_security_status() {
    local os=$(get_os)
    echo -e "${BLUE}${BOLD}🔒 Security Status:${NC}"
    
    # Check for failed login attempts
    if [ "$os" == "Linux" ]; then
        if command -v journalctl &>/dev/null; then
            local failed_logins=$(journalctl -u ssh --since "24 hours ago" 2>/dev/null | grep -c "Failed password" 2>/dev/null || echo "0")
            # Clean up the output - remove any newlines or extra characters
            failed_logins=$(echo "$failed_logins" | tr -d '\n' | awk '{print $1}')
            if [ -n "$failed_logins" ] && [ "$failed_logins" -gt 10 ] 2>/dev/null; then
                echo -e "${RED}⚠️  High number of failed SSH login attempts: $failed_logins${NC}"
                ((TOTAL_WARNINGS++))
            else
                echo -e "${GREEN}✓ SSH login attempts normal: ${failed_logins:-0}${NC}"
            fi
        fi
        
        # Check for root login attempts
        if command -v last &>/dev/null; then
            local root_attempts=$(last root 2>/dev/null | grep -v "wtmp begins" | wc -l 2>/dev/null || echo "0")
            root_attempts=$(echo "$root_attempts" | tr -d '\n' | awk '{print $1}')
            if [ -n "$root_attempts" ] && [ "$root_attempts" -gt 0 ] 2>/dev/null; then
                echo -e "${YELLOW}⚠️  Recent root login attempts detected: $root_attempts${NC}"
            else
                echo -e "${GREEN}✓ No recent root logins${NC}"
            fi
        fi
        
        # SSH config hardening (basic)
        if [ -f /etc/ssh/sshd_config ]; then
            local permit_root=$(grep -Ei '^[# ]*PermitRootLogin' /etc/ssh/sshd_config 2>/dev/null | tail -1 | awk '{print tolower($2)}')
            if [ "$permit_root" = "yes" ]; then
                echo -e "${YELLOW}⚠️  SSH permits root login${NC}"; ((TOTAL_WARNINGS++))
            else
                echo -e "${GREEN}✓ SSH root login disabled${NC}"
            fi
            local pass_auth=$(grep -Ei '^[# ]*PasswordAuthentication' /etc/ssh/sshd_config 2>/dev/null | tail -1 | awk '{print tolower($2)}')
            if [ "$pass_auth" = "yes" ]; then
                echo -e "${YELLOW}⚠️  SSH password auth enabled${NC}"; ((TOTAL_WARNINGS++))
            else
                echo -e "${GREEN}✓ SSH password auth disabled${NC}"
            fi
        fi

        # Check open ports
        if command -v ss &>/dev/null; then
            local open_ports=$(ss -tuln | grep LISTEN | wc -l 2>/dev/null || echo "0")
            open_ports=$(echo "$open_ports" | tr -d '\n' | awk '{print $1}')
            echo -e "${CYAN}Open listening ports: ${open_ports:-0}${NC}"
        elif command -v netstat &>/dev/null; then
            local open_ports=$(netstat -tuln 2>/dev/null | grep LISTEN | wc -l 2>/dev/null || echo "0")
            open_ports=$(echo "$open_ports" | tr -d '\n' | awk '{print $1}')
            echo -e "${CYAN}Open listening ports: ${open_ports:-0}${NC}"
        fi

        # World-writable directories under /
        local ww_count=$(find / -xdev -type d -perm -0002 2>/dev/null | grep -v "/proc" | head -100 | wc -l 2>/dev/null || echo 0)
        if [ "$ww_count" -gt 0 ]; then
            echo -e "${YELLOW}⚠️  World-writable dirs (top 100 scanned): $ww_count${NC}"; ((TOTAL_WARNINGS++))
        else
            echo -e "${GREEN}✓ No world-writable dirs (scanned)${NC}"
        fi

        # Sudo failures (last 24h)
        if command -v journalctl &>/dev/null; then
            local sudo_fails_raw
            sudo_fails_raw=$(journalctl _COMM=sudo --since "24 hours ago" 2>/dev/null | grep -ci 'authentication failure' || echo 0)
            local sudo_fails=$(echo "$sudo_fails_raw" | tr -cd '0-9' )
            [ -z "$sudo_fails" ] && sudo_fails=0
            if [ "$sudo_fails" -gt 0 ] 2>/dev/null; then
                echo -e "${YELLOW}⚠️  Sudo authentication failures: $sudo_fails${NC}"; ((TOTAL_WARNINGS++))
            else
                echo -e "${GREEN}✓ No sudo authentication failures${NC}"
            fi
        fi
    fi
}

check_system_updates() {
    local os=$(get_os)
    echo -e "${BLUE}${BOLD}📦 System Updates:${NC}"
    
    if [ "$os" == "Linux" ]; then
        if command -v apt &>/dev/null; then
            local updates=$(apt list --upgradable 2>/dev/null | grep -c upgradable 2>/dev/null || echo "0")
            # Clean up the output
            updates=$(echo "$updates" | tr -d '\n' | awk '{print $1}')
            if [ -n "$updates" ] && [ "$updates" -gt 1 ] 2>/dev/null; then
                echo -e "${YELLOW}Available updates: $((updates - 1))${NC}"
            else
                echo -e "${GREEN}System is up to date${NC}"
            fi
        elif command -v yum &>/dev/null; then
            local updates=$(yum check-update 2>/dev/null | grep -c "^[a-zA-Z]" 2>/dev/null || echo "0")
            updates=$(echo "$updates" | tr -d '\n' | awk '{print $1}')
            if [ -n "$updates" ] && [ "$updates" -gt 0 ] 2>/dev/null; then
                echo -e "${YELLOW}Available updates: $updates${NC}"
            else
                echo -e "${GREEN}System is up to date${NC}"
            fi
        elif command -v dnf &>/dev/null; then
            local updates=$(dnf check-update 2>/dev/null | grep -c "^[a-zA-Z]" 2>/dev/null || echo "0")
            updates=$(echo "$updates" | tr -d '\n' | awk '{print $1}')
            if [ -n "$updates" ] && [ "$updates" -gt 0 ] 2>/dev/null; then
                echo -e "${YELLOW}Available updates: $updates${NC}"
            else
                echo -e "${GREEN}System is up to date${NC}"
            fi
        elif command -v pacman &>/dev/null; then
            local updates=$(pacman -Sup 2>/dev/null | grep -c ".pkg.tar" || echo 0)
            if [ "$updates" -gt 0 ]; then echo -e "${YELLOW}Available updates: $updates${NC}"; else echo -e "${GREEN}System is up to date${NC}"; fi
        elif command -v zypper &>/dev/null; then
            local updates=$(zypper list-updates 2>/dev/null | grep -c '^v ' || echo 0)
            if [ "$updates" -gt 0 ]; then echo -e "${YELLOW}Available updates: $updates${NC}"; else echo -e "${GREEN}System is up to date${NC}"; fi
        elif command -v apk &>/dev/null; then
            local updates=$(apk version -l '<' 2>/dev/null | grep -c '<' || echo 0)
            if [ "$updates" -gt 0 ]; then echo -e "${YELLOW}Available updates: $updates${NC}"; else echo -e "${GREEN}System is up to date${NC}"; fi
        else
            echo -e "${YELLOW}Package manager not found${NC}"
        fi
    elif [ "$os" == "Mac" ]; then
        if command -v softwareupdate &>/dev/null; then
            local updates=$(softwareupdate -l 2>/dev/null | grep -c "recommended" 2>/dev/null || echo "0")
            updates=$(echo "$updates" | tr -d '\n' | awk '{print $1}')
            if [ -n "$updates" ] && [ "$updates" -gt 0 ] 2>/dev/null; then
                echo -e "${YELLOW}Available updates: $updates${NC}"
            else
                echo -e "${GREEN}System is up to date${NC}"
            fi
        fi
    fi
}

run_security_scan() {
    echo -e "${MAGENTA}${BOLD}🔍 Running Security Scan...${NC}"
    log_message "Starting security scan" "INFO"
    
    draw_line
    check_security_status
    echo
    
    # Check firewall status
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then
        echo -e "${BLUE}${BOLD}Firewall Status:${NC}"
        if command -v ufw &>/dev/null; then
            ufw status 2>/dev/null || echo -e "${YELLOW}UFW status unavailable${NC}"
        elif command -v firewall-cmd &>/dev/null; then
            firewall-cmd --state 2>/dev/null || echo -e "${YELLOW}Firewall status unavailable${NC}"
        else
            echo -e "${YELLOW}No firewall tool detected${NC}"
        fi
        echo
    fi
    
    # Check for suspicious processes
    echo -e "${BLUE}${BOLD}Process Analysis:${NC}"
    if command -v ps &>/dev/null; then
        local suspicious_processes=$(ps aux | grep -E "(nc|netcat|nmap|tcpdump)" | grep -v grep | wc -l)
        if [ "$suspicious_processes" -gt 0 ]; then
            echo -e "${YELLOW}⚠️  Potential network monitoring tools detected${NC}"
        else
            echo -e "${GREEN}✓ No suspicious processes detected${NC}"
        fi
    else
        echo -e "${YELLOW}Process analysis not available${NC}"
    fi
    echo
    
    check_network_services
    echo
    
    echo -e "${BLUE}${BOLD}Security Scan Complete${NC}"
    draw_line
}

run_performance_test() {
    echo -e "${MAGENTA}${BOLD}🚀 Running Performance Tests...${NC}"
    log_message "Starting performance tests" "INFO"
    
    draw_line
    
    # CPU performance test
    echo -e "${BLUE}${BOLD}CPU Performance Test:${NC}"
    local start_time=$(date +%s.%N 2>/dev/null || date +%s)
    if command -v bc &>/dev/null; then
        echo "scale=1000; 4*a(1)" | bc -l > /dev/null 2>&1 || echo "Pi calculation completed"
    else
        # Simple CPU test without bc
        local i=0
        while [ $i -lt 10000 ]; do
            i=$((i + 1))
        done
    fi
    local end_time=$(date +%s.%N 2>/dev/null || date +%s)
    
    if command -v bc &>/dev/null; then
        local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "N/A")
        echo -e "${CYAN}CPU test duration: ${duration}s${NC}"
    else
        echo -e "${CYAN}CPU test completed${NC}"
    fi
    echo
    
    # Memory performance test
    echo -e "${BLUE}${BOLD}Memory Performance:${NC}"
    get_memory_usage
    echo
    
    # Disk I/O test (simple)
    echo -e "${BLUE}${BOLD}Disk I/O Test:${NC}"
    local disk_test_start=$(date +%s.%N 2>/dev/null || date +%s)
    if command -v dd &>/dev/null; then
        local dd_output
        dd_output=$( (dd if=/dev/zero of=/tmp/test_file bs=1M count=10 conv=fdatasync 2>&1) ); rm -f /tmp/test_file 2>/dev/null || true
        local disk_test_end=$(date +%s.%N 2>/dev/null || date +%s)
        if command -v bc &>/dev/null; then
            local disk_duration=$(echo "$disk_test_end - $disk_test_start" | bc 2>/dev/null || echo "N/A")
            local speed=$(echo "$dd_output" | grep -Eo '[0-9.]+ MB/s' | tail -1)
            echo -e "${CYAN}10MB write test: ${disk_duration}s ${speed:+| Speed: $speed}${NC}"
        else
            echo -e "${CYAN}10MB write test completed${NC}"
        fi
    else
        echo -e "${YELLOW}dd command not available for I/O test${NC}"
    fi
    echo
    
    echo -e "${BLUE}${BOLD}Performance Test Complete${NC}"
    draw_line
}

run_health_check() {
    echo -e "${MAGENTA}${BOLD}🏥 Running System Health Check...${NC}"
    log_message "Starting health check" "INFO"
    
    draw_line
    
    # Check critical services
    echo -e "${BLUE}${BOLD}Critical Services:${NC}"
    local services=("ssh" "cron" "systemd-logind")
    for service in "${services[@]}"; do
        check_service "$service"
    done
    echo
    
    # Check disk health
    check_disk_health
    echo
    
    # Check system resources
    echo -e "${BLUE}${BOLD}Resource Thresholds:${NC}"
    local cpu_usage=$(parse_cpu_percentage "$(get_cpu_usage)")
    local mem_percentage=$(get_memory_percentage)
    local disk_percentage=$(get_disk_percentage)
    
    if [ "$ENABLE_ALERTS" = true ]; then
        check_threshold "$cpu_usage" "$ALERT_THRESHOLD_CPU" "CPU usage"
        check_threshold "$mem_percentage" "$ALERT_THRESHOLD_MEM" "Memory usage"
        check_threshold "$disk_percentage" "$ALERT_THRESHOLD_DISK" "Disk usage"
    fi
    
    echo -e "${CYAN}CPU Usage: ${cpu_usage}% (Threshold: ${ALERT_THRESHOLD_CPU}%)${NC}"
    echo -e "${CYAN}Memory Usage: ${mem_percentage}% (Threshold: ${ALERT_THRESHOLD_MEM}%)${NC}"
    echo -e "${CYAN}Disk Usage: ${disk_percentage}% (Threshold: ${ALERT_THRESHOLD_DISK}%)${NC}"
    echo
    
    check_system_updates
    echo
    
    echo -e "${BLUE}${BOLD}Health Check Complete${NC}"
    if [ "$TOTAL_WARNINGS" -eq 0 ] && [ "$TOTAL_ERRORS" -eq 0 ]; then
        echo -e "${GREEN}✓ System appears to be healthy${NC}"
    else
        echo -e "${YELLOW}⚠️  Found $TOTAL_WARNINGS warnings and $TOTAL_ERRORS errors${NC}"
    fi
    draw_line
}

generate_json_report() {
    local output_file="$1"
    local cpu_usage=$(parse_cpu_percentage "$(get_cpu_usage)")
    local mem_percentage=$(get_memory_percentage)
    local disk_percentage=$(get_disk_percentage)
        local mem_details="$(escape_json "$(get_memory_usage)")"
        local storage_details="$(escape_json "$(get_storage_usage | tail -1)")"
        local uptime="$(escape_json "$(get_uptime_info)")"
        local loadavg="$(escape_json "$(get_load_average)")"
        local envdet="$(escape_json "$(detect_environment)")"
        local ipaddr="$(escape_json "$(get_ip_info)")"
        local cputemp="$(escape_json "$(get_cpu_temperature)")"

        cat > "$output_file" << EOF
{
    "timestamp": "$(date -Iseconds 2>/dev/null || date)",
    "hostname": "$(hostname)",
    "environment": "$envdet",
    "system": {
        "os": "$(uname -srm)",
        "uptime": "$uptime",
        "load_average": "$loadavg"
    },
    "cpu": {
        "cores": $(get_cpu_count),
        "usage_percent": $cpu_usage,
        "temperature": "$cputemp"
    },
    "memory": {
        "usage_percent": $mem_percentage,
        "details": "$mem_details"
    },
    "storage": {
        "root_usage_percent": $disk_percentage,
        "details": "$storage_details"
    },
    "network": {
        "primary_ip": "$ipaddr"
    },
    "alerts": {
        "warnings": $TOTAL_WARNINGS,
        "errors": $TOTAL_ERRORS
    },
    "summary": "status=$([ "$TOTAL_ERRORS" -gt 0 ] && echo ERROR || ( [ "$TOTAL_WARNINGS" -gt 0 ] && echo WARN || echo OK ));warnings=$TOTAL_WARNINGS;errors=$TOTAL_ERRORS"
}
EOF
}

generate_html_report() {
    local output_file="$1"
    local cpu_usage=$(parse_cpu_percentage "$(get_cpu_usage)")
    local mem_percentage=$(get_memory_percentage)
    local disk_percentage=$(get_disk_percentage)
    local status_class
    if [ "$TOTAL_ERRORS" -gt 0 ]; then status_class="error"; elif [ "$TOTAL_WARNINGS" -gt 0 ]; then status_class="warning"; else status_class="success"; fi
    local envdet="$(html_safe "$(detect_environment)")"
    
    cat > "$output_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Server Report - $(hostname)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f4f4f4; padding: 20px; border-radius: 5px; }
        .section { margin: 20px 0; }
        .metric { background: #e8f4f8; padding: 10px; margin: 5px 0; border-radius: 3px; }
        .warning { background: #fff3cd; color: #856404; }
        .error { background: #f8d7da; color: #721c24; }
        .success { background: #d4edda; color: #155724; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Server Information Report</h1>
    <p><strong>Hostname:</strong> $(html_safe "$(hostname)")</p>
    <p><strong>Generated:</strong> $(html_safe "$(date)")</p>
    <p><strong>OS:</strong> $(html_safe "$(uname -srm)")</p>
    <p><strong>Environment:</strong> $envdet</p>
    </div>
    
    <div class="section">
        <h2>System Resources</h2>
        <div class="metric">
            <strong>CPU Usage:</strong> ${cpu_usage}% (${ALERT_THRESHOLD_CPU}% threshold)
        </div>
        <div class="metric">
            <strong>Memory Usage:</strong> ${mem_percentage}% (${ALERT_THRESHOLD_MEM}% threshold)
        </div>
        <div class="metric">
            <strong>Disk Usage:</strong> ${disk_percentage}% (${ALERT_THRESHOLD_DISK}% threshold)
        </div>
        <div class="metric">
            <strong>Load Average:</strong> $(html_safe "$(get_load_average)")
        </div>
        <div class="metric">
            <strong>Uptime:</strong> $(html_safe "$(get_uptime_info)")
        </div>
    </div>
    
    <div class="section">
        <h2>Alert Summary</h2>
        <div class="metric $status_class"><strong>Status:</strong> $([ "$TOTAL_ERRORS" -gt 0 ] && echo ERROR || ( [ "$TOTAL_WARNINGS" -gt 0 ] && echo WARN || echo OK ))</div>
        <div class="metric"><strong>Warnings:</strong> $TOTAL_WARNINGS</div>
        <div class="metric"><strong>Errors:</strong> $TOTAL_ERRORS</div>
    </div>
</body>
</html>
EOF
}

monitoring_mode() {
    echo -e "${MAGENTA}${BOLD}Starting continuous monitoring mode (interval: ${MONITOR_INTERVAL}s)...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    
    while true; do
        TOTAL_WARNINGS=0; TOTAL_ERRORS=0; REPORT_START_TIME=$(date +%s)
        clear
        main_report
        echo -e "\n${DIM}Refreshing in ${MONITOR_INTERVAL} seconds...${NC}"
        sleep "$MONITOR_INTERVAL"
    done
}

main_report() {
    if [ "$QUIET_MODE" = false ]; then
        echo -e "${BOLD}${BLUE}Advanced Server Information Report${NC}"
        echo -e "${DIM}Generated on $(date)${NC}"
        draw_line
    fi
    
    log_message "Starting server report generation" "INFO"
    
    # System Information
    if [ "$QUIET_MODE" = false ]; then
        echo -e "${BOLD}${CYAN}📊 System Information${NC}"
        echo -e "${BLUE}Hostname:${NC} $(hostname)"
        echo -e "${BLUE}OS:${NC} $(uname -srm)"
        echo -e "${BLUE}Environment:${NC} $(detect_environment)"
        echo -e "${BLUE}Uptime:${NC} $(get_uptime_info)"
        echo -e "${BLUE}Load Average:${NC} $(get_load_average)"
        echo
    fi
    
    # CPU Information
    if [ "$QUIET_MODE" = false ]; then
        echo -e "${BOLD}${CYAN}💻 CPU Information${NC}"
        echo -e "${BLUE}CPU Cores:${NC} $(get_cpu_count)"
        local cpu_usage=$(get_cpu_usage)
        echo -e "${BLUE}CPU Usage:${NC} ${cpu_usage}%"
        echo -e "${BLUE}CPU Temperature:${NC} $(get_cpu_temperature)"
        
        # Check CPU threshold
        if [ "$ENABLE_ALERTS" = true ]; then
            local cpu_percent=$(parse_cpu_percentage "$cpu_usage")
            check_threshold "$cpu_percent" "$ALERT_THRESHOLD_CPU" "CPU usage"
        fi
        echo
    fi
    
    # Memory Information
    if [ "$QUIET_MODE" = false ]; then
        echo -e "${BOLD}${CYAN}🧠 Memory Information${NC}"
        echo -e "${BLUE}Memory Usage:${NC} $(get_memory_usage)"
        
        # Check memory threshold
        if [ "$ENABLE_ALERTS" = true ]; then
            local mem_percent=$(get_memory_percentage)
            check_threshold "$mem_percent" "$ALERT_THRESHOLD_MEM" "Memory usage"
        fi
        echo
    fi
    
    # Storage Information
    if [ "$QUIET_MODE" = false ]; then
        echo -e "${BOLD}${CYAN}💾 Storage Information${NC}"
        get_storage_usage
        
        # Check disk threshold
        if [ "$ENABLE_ALERTS" = true ]; then
            local disk_percent=$(get_disk_percentage)
            check_threshold "$disk_percent" "$ALERT_THRESHOLD_DISK" "Disk usage"
        fi
        
        if [ "$DETAILED_MODE" = true ]; then
            echo
            check_disk_health
        fi
        echo
    fi
    
    # Network Information
    if [ "$QUIET_MODE" = false ]; then
        echo -e "${BOLD}${CYAN}🌐 Network Information${NC}"
        echo -e "${BLUE}Primary IP:${NC} $(get_ip_info)"
        
        if [ "$DETAILED_MODE" = true ]; then
            echo
            check_network_services
        fi
        echo
    fi
    
    # Services Check
    if [ "$DETAILED_MODE" = true ] && [ "$QUIET_MODE" = false ]; then
        echo -e "${BOLD}${CYAN}🔧 Services Status${NC}"
        if [ -n "$CUSTOM_SERVICES" ]; then
            IFS=',' read -r -a svc_array <<< "$CUSTOM_SERVICES"
            for svc in "${svc_array[@]}"; do
                [ -n "$svc" ] && check_service "$svc"
            done
        else
            check_service ssh
            check_service cron
        fi
        check_docker_containers
        echo
    fi
    
    # Process Information
    if [ "$DETAILED_MODE" = true ] && [ "$QUIET_MODE" = false ]; then
        get_process_info
        echo
    fi
    
    # Security and Updates
    if [ "$DETAILED_MODE" = true ] && [ "$QUIET_MODE" = false ]; then
        check_security_status
        echo
        check_system_updates
        echo
    fi
    
    # Summary
    if [ "$QUIET_MODE" = false ]; then
        local end_time=$(date +%s)
        local duration=$((end_time - REPORT_START_TIME))
        
        echo -e "${BOLD}${CYAN}📋 Summary${NC}"
        echo -e "${BLUE}Report Duration:${NC} ${duration} seconds"
        echo -e "${BLUE}Total Warnings:${NC} $TOTAL_WARNINGS"
        echo -e "${BLUE}Total Errors:${NC} $TOTAL_ERRORS"
        
        if [ "$TOTAL_WARNINGS" -eq 0 ] && [ "$TOTAL_ERRORS" -eq 0 ]; then
            echo -e "${GREEN}✓ System status: OK${NC}"
        else
            echo -e "${YELLOW}⚠ System status: Attention required${NC}"
        fi
        
        draw_line
    fi
    
    log_message "Server report completed. Warnings: $TOTAL_WARNINGS, Errors: $TOTAL_ERRORS" "INFO"
}

# Command line argument parsing
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--detailed)
                DETAILED_MODE=true
                shift
                ;;
            -q|--quiet)
                QUIET_MODE=true
                shift
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                ENABLE_EXPORT=true
                shift 2
                ;;
            -f|--format)
                EXPORT_FORMAT="$2"
                shift 2
                ;;
            --no-log)
                ENABLE_LOGGING=false
                shift
                ;;
            --no-alerts)
                ENABLE_ALERTS=false
                shift
                ;;
            --cpu-threshold)
                ALERT_THRESHOLD_CPU="$2"
                shift 2
                ;;
            --mem-threshold)
                ALERT_THRESHOLD_MEM="$2"
                shift 2
                ;;
            --disk-threshold)
                ALERT_THRESHOLD_DISK="$2"
                shift 2
                ;;
            --monitor)
                MONITOR_MODE_REQUESTED=true
                shift
                ;;
            --interval)
                MONITOR_INTERVAL="$2"; shift 2 ;;
            --no-color)
                disable_colors; shift ;;
            --security-scan)
                run_security_scan
                exit 0
                ;;
            --performance-test)
                run_performance_test
                exit 0
                ;;
            --health-check)
                run_health_check
                exit 0
                ;;
            --services)
                CUSTOM_SERVICES="$2"; shift 2 ;;
            --version)
                echo "infoReport version $VERSION"; exit 0 ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main execution function
main() {
    # Auto-disable colors if not a TTY
    if [ ! -t 1 ]; then disable_colors; fi

    parse_arguments "$@"

    if [ "$MONITOR_MODE_REQUESTED" = true ]; then
        monitoring_mode
        exit 0
    fi

    main_report

    # Export if requested (use quiet to avoid duplication for txt)
    if [ "$ENABLE_EXPORT" = true ] && [ -n "$OUTPUT_FILE" ]; then
        case "${EXPORT_FORMAT:-txt}" in
            json)
                generate_json_report "$OUTPUT_FILE"
                echo -e "${GREEN}Report exported to: $OUTPUT_FILE (JSON format)${NC}"
                ;;
            txt)
                QUIET_MODE=true main_report > "$OUTPUT_FILE" 2>&1
                echo -e "${GREEN}Report exported to: $OUTPUT_FILE (TXT format)${NC}"
                ;;
            html)
                generate_html_report "$OUTPUT_FILE"
                echo -e "${GREEN}Report exported to: $OUTPUT_FILE (HTML format)${NC}"
                ;;
            *)
                echo -e "${RED}Unsupported export format: $EXPORT_FORMAT${NC}"
                exit 1
                ;;
        esac
    fi

    # Exit code semantics: 0 ok, 1 warnings only, 2 errors (or warnings+errors)
    if [ "$TOTAL_ERRORS" -gt 0 ]; then
        exit 2
    elif [ "$TOTAL_WARNINGS" -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
