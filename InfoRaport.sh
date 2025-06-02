#!/bin/bash

# Advanced Server Information Report Tool
# Version: 2.0
# Author: 0xPacman
# License: MIT

# Color definitions and formatting
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

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/server_report.log"
CONFIG_FILE="${SCRIPT_DIR}/config.ini"
ENABLE_LOGGING=true
ENABLE_ALERTS=true
ENABLE_EXPORT=true
ALERT_THRESHOLD_CPU=80
ALERT_THRESHOLD_MEM=85
ALERT_THRESHOLD_DISK=90
DETAILED_MODE=false
QUIET_MODE=false

# Global variables
TOTAL_WARNINGS=0
TOTAL_ERRORS=0
REPORT_START_TIME=$(date +%s)

# Utility functions (needed before module loading)
log_message() {
    local message="$1"
    local level="${2:-INFO}"
    if [ "$ENABLE_LOGGING" = true ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
    fi
}

# Module loading
load_modules() {
    local modules=("security_scanner" "performance_benchmark" "html_generator" "email_notifications" "health_checker")
    
    for module in "${modules[@]}"; do
        local module_file="${SCRIPT_DIR}/${module}.sh"
        if [ -f "$module_file" ]; then
            source "$module_file"
            log_message "Loaded module: $module" "DEBUG"
        else
            log_message "Module not found: $module_file" "WARN"
        fi
    done
}

# Load modules at startup
load_modules


# Other utility functions
show_help() {
    cat << EOF
${BOLD}Advanced Server Information Report Tool${NC}

${UNDERLINE}Usage:${NC}
    $(basename "$0") [OPTIONS]

${UNDERLINE}Options:${NC}
    -h, --help          Show this help message
    -d, --detailed      Enable detailed mode with additional information
    -q, --quiet         Run in quiet mode (minimal output)
    -o, --output FILE   Export report to specified file
    -f, --format FORMAT Export format (txt, json, html) [default: txt]
    -c, --config FILE   Use custom configuration file
    --no-log           Disable logging
    --no-alerts        Disable alert checking
    --cpu-threshold N  Set CPU alert threshold (default: 80%)
    --mem-threshold N  Set memory alert threshold (default: 85%)
    --disk-threshold N Set disk alert threshold (default: 90%)
    --check-services   Check additional services
    --monitor          Run in continuous monitoring mode
    --report-only      Generate report without displaying
    --security-scan    Run comprehensive security scan
    --performance-test Run performance benchmarks
    --health-check     Run system health check
    --email-test       Test email notification configuration
    --recommendations  Show system optimization recommendations

${UNDERLINE}Examples:${NC}
    $(basename "$0") -d -o report.html -f html
    $(basename "$0") --monitor --cpu-threshold 90
    $(basename "$0") -q --report-only -o status.json -f json
    $(basename "$0") --security-scan --detailed
    $(basename "$0") --health-check --recommendations

EOF
}

check_threshold() {
    local value="$1"
    local threshold="$2"
    local metric="$3"
    
    if (( $(echo "$value > $threshold" | bc -l) )); then
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

get_os() {
    case "$(uname -s)" in
        Linux*)   echo "Linux" ;;
        Darwin*)  echo "Mac" ;;
        *)        echo "Other" ;;
    esac
}

draw_line() {
    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
}


get_cpu_usage() {
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then
        top -bn1 | grep "Cpu(s)" | awk -F',' '{print $1}' | awk -F':' '{print $2}' | sed 's/^[ \t]*//'
    elif [ "$os" == "Mac" ]; then
        top -l 1 | grep "CPU usage" | sed 's/^[ \t]*//'
    else
        echo "N/A"
    fi
}

get_cpu_count() {
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then
        nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo
    elif [ "$os" == "Mac" ]; then
        sysctl -n hw.ncpu 2>/dev/null
    else
        echo "N/A"
    fi
}

get_memory_usage() {
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then

        free -m | awk 'NR==2 {printf "Total: %s MB | Used: %s MB | Free: %s MB | Shared: %s MB | Buff/Cache: %s MB | Available: %s MB", $2,$3,$4,$5,$6,$7}'
    elif [ "$os" == "Mac" ]; then
        top -l 1 | grep "PhysMem" | sed 's/^[ \t]*//'
    else
        echo "Memory info not available."
    fi
}


get_storage_usage() {
    df -h / | awk 'NR==1 || NR==2'
}

# Additional system information functions
get_uptime_info() {
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then
        uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}'
    elif [ "$os" == "Mac" ]; then
        uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}'
    else
        uptime
    fi
}

get_load_average() {
    local os=$(get_os)
    if [ "$os" == "Linux" ] || [ "$os" == "Mac" ]; then
        uptime | awk -F'load average: ' '{print $2}'
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
        
        # Try lm-sensors
        if command -v cat /proc/cpuinfo &>/dev/null; then
            echo "N/A (install lm-sensors for temperature)"
        else
            echo "N/A"
        fi
    elif [ "$os" == "Mac" ]; then
        # macOS temperature monitoring requires additional tools
        echo "N/A (install additional tools for temperature)"
    else
        echo "N/A"
    fi
}

get_memory_percentage() {
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then
        local mem_info=$(free | grep Mem)
        local total=$(echo "$mem_info" | awk '{print $2}')
        local used=$(echo "$mem_info" | awk '{print $3}')
        if [ -n "$total" ] && [ "$total" -gt 0 ]; then
            echo "scale=1; $used * 100 / $total" | bc -l 2>/dev/null | cut -d. -f1
        else
            echo "N/A"
        fi
    elif [ "$os" == "Mac" ]; then
        # macOS memory calculation is more complex
        local page_size=$(vm_stat | grep "page size" | awk '{print $8}')
        local pages_free=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        local pages_active=$(vm_stat | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
        local pages_inactive=$(vm_stat | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
        local pages_speculative=$(vm_stat | grep "Pages speculative" | awk '{print $3}' | sed 's/\.//')
        local pages_wired=$(vm_stat | grep "Pages wired down" | awk '{print $4}' | sed 's/\.//')
        
        if [ -n "$page_size" ] && [ -n "$pages_free" ]; then
            local total_pages=$((pages_free + pages_active + pages_inactive + pages_speculative + pages_wired))
            local used_pages=$((pages_active + pages_inactive + pages_wired))
            if [ "$total_pages" -gt 0 ]; then
                echo "scale=1; $used_pages * 100 / $total_pages" | bc -l 2>/dev/null | cut -d. -f1
            else
                echo "N/A"
            fi
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

get_disk_percentage() {
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ -n "$disk_usage" ] && [[ "$disk_usage" =~ ^[0-9]+$ ]]; then
        echo "$disk_usage"
    else
        echo "0"
    fi
}

check_disk_health() {
    echo -e "${BLUE}${BOLD}🔍 Disk Health Check:${NC}"
    
    # Check if smartctl is available
    if command -v smartctl &>/dev/null; then
        local disk_devices=$(lsblk -dnbo NAME | grep -E '^(sd|nvme|hd)')
        if [ -n "$disk_devices" ]; then
            while IFS= read -r device; do
                echo -e "${CYAN}Checking /dev/$device:${NC}"
                local smart_status=$(smartctl -H "/dev/$device" 2>/dev/null | grep "SMART overall-health" | awk '{print $NF}')
                if [ "$smart_status" = "PASSED" ]; then
                    echo -e "${GREEN}  ✓ SMART Status: PASSED${NC}"
                elif [ -n "$smart_status" ]; then
                    echo -e "${RED}  ✗ SMART Status: $smart_status${NC}"
                else
                    echo -e "${YELLOW}  ? SMART Status: Unable to determine${NC}"
                fi
            done <<< "$disk_devices"
        else
            echo -e "${YELLOW}No suitable disk devices found for SMART check${NC}"
        fi
    else
        echo -e "${YELLOW}smartctl not available (install smartmontools for disk health check)${NC}"
    fi
    
    # Check disk space on all mounted filesystems
    echo -e "${CYAN}Disk Space Analysis:${NC}"
    df -h | grep -E '^/dev/' | while IFS= read -r line; do
        local usage=$(echo "$line" | awk '{print $5}' | sed 's/%//')
        local filesystem=$(echo "$line" | awk '{print $1}')
        local mountpoint=$(echo "$line" | awk '{print $6}')
        
        if [ -n "$usage" ] && [[ "$usage" =~ ^[0-9]+$ ]]; then
            if [ "$usage" -ge 90 ]; then
                echo -e "${RED}  ⚠️  $filesystem ($mountpoint): ${usage}% - CRITICAL${NC}"
            elif [ "$usage" -ge 80 ]; then
                echo -e "${YELLOW}  ⚠️  $filesystem ($mountpoint): ${usage}% - WARNING${NC}"
            else
                echo -e "${GREEN}  ✓ $filesystem ($mountpoint): ${usage}% - OK${NC}"
            fi
        fi
    done
}

get_process_info() {
    echo -e "${BLUE}${BOLD}🔄 Process Information:${NC}"
    
    # Top CPU processes
    echo -e "${CYAN}Top 5 CPU consuming processes:${NC}"
    if command -v ps &>/dev/null; then
        ps aux --sort=-%cpu | head -6 | tail -5 | while IFS= read -r line; do
            echo -e "${CYAN}  $line${NC}"
        done
    fi
    
    echo ""
    
    # Top Memory processes
    echo -e "${CYAN}Top 5 Memory consuming processes:${NC}"
    if command -v ps &>/dev/null; then
        ps aux --sort=-%mem | head -6 | tail -5 | while IFS= read -r line; do
            echo -e "${CYAN}  $line${NC}"
        done
    fi
    
    echo ""
    
    # Process count
    local total_processes=$(ps aux | wc -l)
    echo -e "${CYAN}Total running processes: $((total_processes - 1))${NC}"
    
    # Load average explanation
    local load_avg=$(get_load_average)
    local cpu_count=$(get_cpu_count)
    echo -e "${CYAN}Load Average: $load_avg (CPU cores: $cpu_count)${NC}"
    
    if [ -n "$cpu_count" ] && [[ "$cpu_count" =~ ^[0-9]+$ ]]; then
        local load_1min=$(echo "$load_avg" | awk -F', ' '{print $1}' | xargs)
        if [ -n "$load_1min" ] && [[ "$load_1min" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            local load_percentage=$(echo "scale=1; $load_1min * 100 / $cpu_count" | bc -l 2>/dev/null)
            if [ -n "$load_percentage" ]; then
                echo -e "${CYAN}Load percentage: ${load_percentage}%${NC}"
                if (( $(echo "$load_percentage > 100" | bc -l 2>/dev/null) )); then
                    echo -e "${RED}  ⚠️  System is overloaded!${NC}"
                elif (( $(echo "$load_percentage > 80" | bc -l 2>/dev/null) )); then
                    echo -e "${YELLOW}  ⚠️  High system load${NC}"
                else
                    echo -e "${GREEN}  ✓ Load is normal${NC}"
                fi
            fi
        fi
    fi
}


check_service() {
    local service_name="$1"
    local os=$(get_os)
    local status=""
    local details=""

    if [ "$os" == "Linux" ]; then
        if command -v systemctl &>/dev/null; then
            status=$(systemctl is-active "$service_name" 2>/dev/null)
            if [[ "$status" == "active" || "$status" == "running" ]]; then
                echo -e "${GREEN}${BOLD}$service_name: Active${NC}"
            elif [[ "$status" == "inactive" || "$status" == "stopped" ]]; then
                echo -e "${RED}${BOLD}$service_name: Inactive${NC}"
            else
                echo -e "${YELLOW}${BOLD}$service_name: $status${NC}"
                if command -v journalctl &>/dev/null; then
                    details=$(journalctl -u "$service_name" -n 5 --no-pager 2>/dev/null)
                    if [ -n "$details" ]; then
                        echo -e "${CYAN}Log Details (last 5 lines):${NC}"
                        echo -e "${CYAN}$details${NC}"
                    fi
                fi
            fi
        else

            service "$service_name" status &>/dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}${BOLD}$service_name: Active${NC}"
            else
                echo -e "${RED}${BOLD}$service_name: Inactive${NC}"
            fi
        fi
    elif [ "$os" == "Mac" ]; then
        if [ "$service_name" == "ssh" ]; then
            status=$(systemsetup -getremotelogin 2>/dev/null | awk '{print $3}')
            if [[ "$status" == "On" ]]; then
                echo -e "${GREEN}${BOLD}SSH: Active${NC}"
            else
                echo -e "${RED}${BOLD}SSH: Inactive${NC}"
            fi
        elif [ "$service_name" == "firewall" ]; then
            fw=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null)
            if [ "$fw" -eq 0 ]; then
                echo -e "${RED}${BOLD}Firewall: Off${NC}"
            else
                echo -e "${GREEN}${BOLD}Firewall: On${NC}"
            fi
        else
            echo -e "${YELLOW}${BOLD}$service_name: N/A on macOS${NC}"
        fi
    else
        echo -e "${YELLOW}${BOLD}$service_name: N/A${NC}"
    fi
}

check_network_services() {
    local os=$(get_os)
    echo -e "${BLUE}${BOLD}Network Management Services:${NC}"
    if [ "$os" == "Linux" ]; then
        local services=("NetworkManager" "systemd-networkd")
        for svc in "${services[@]}"; do
            if command -v systemctl &>/dev/null; then
                local status=$(systemctl is-active "$svc" 2>/dev/null)
                if [[ "$status" == "active" || "$status" == "running" ]]; then
                    echo -e "${GREEN}$svc: Active${NC}"
                elif [[ "$status" == "inactive" || "$status" == "stopped" ]]; then
                    echo -e "${RED}$svc: Inactive${NC}"
                else
                    echo -e "${YELLOW}$svc: $status${NC}"
                    if command -v journalctl &>/dev/null; then
                        local details
                        details=$(journalctl -u "$svc" -n 5 --no-pager 2>/dev/null)
                        if [ -n "$details" ]; then
                            echo -e "${CYAN}Log Details for $svc (last 5 lines):${NC}"
                            echo -e "${CYAN}$details${NC}"
                        fi
                    fi
                fi
            else
                echo -e "${YELLOW}$svc: Cannot check service (systemctl not available)${NC}"
            fi
        done
    elif [ "$os" == "Mac" ]; then
        echo "Network management is handled by macOS system settings."
    else
        echo "N/A"
    fi
}

get_ip_info() {
    if command -v ip &>/dev/null; then
        ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}'
    else
        ifconfig | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}'
    fi
}

get_network_config() {
    if command -v ip &>/dev/null; then
        ip addr
    else
        ifconfig
    fi
}


main_report() {
    log_message "Starting server report generation"
    
    if [ "$QUIET_MODE" = false ]; then
        clear
        echo -e "${MAGENTA}${BOLD}==================================================${NC}"
        echo -e "${MAGENTA}${BOLD}           ADVANCED SERVER MONITOR REPORT         ${NC}"
        echo -e "${MAGENTA}${BOLD}==================================================${NC}"
        echo -e "${YELLOW}Time: $(date)${NC}"
        echo -e "${CYAN}Hostname: $(hostname)${NC}"
        echo -e "${CYAN}Report ID: $(date +%s)${NC}"
        draw_line
    fi

    # System Information
    if [ "$QUIET_MODE" = false ]; then
        echo -e "${BLUE}${BOLD}📊 System Information:${NC}"
        echo -e "${CYAN}OS & Kernel: $(uname -srm)${NC}"
        echo -e "${CYAN}Uptime: $(get_uptime_info)${NC}"
        echo -e "${CYAN}Load Average: $(get_load_average)${NC}"
        draw_line
    fi

    # CPU Information with alerts
    if [ "$QUIET_MODE" = false ]; then
        echo -e "${BLUE}${BOLD}🖥️  CPU Information:${NC}"
        echo -e "${CYAN}Total Cores: $(get_cpu_count)${NC}"
        local cpu_usage_raw=$(get_cpu_usage)
        echo -e "${CYAN}Usage: $cpu_usage_raw${NC}"
        local cpu_temp=$(get_cpu_temperature)
        echo -e "${CYAN}Temperature: $cpu_temp${NC}"
        
        # CPU threshold check
        local cpu_percent=$(parse_cpu_percentage "$cpu_usage_raw")
        if [ -n "$cpu_percent" ] && [ "$ENABLE_ALERTS" = true ]; then
            check_threshold "$cpu_percent" "$ALERT_THRESHOLD_CPU" "CPU usage"
        fi
        draw_line
    fi

    # Memory Information with alerts
    if [ "$QUIET_MODE" = false ]; then
        echo -e "${BLUE}${BOLD}💾 Memory Information:${NC}"
        echo -e "${CYAN}$(get_memory_usage)${NC}"
        
        # Memory threshold check
        local mem_percent=$(get_memory_percentage)
        if [ "$mem_percent" != "N/A" ] && [ "$ENABLE_ALERTS" = true ]; then
            echo -e "${CYAN}Memory Usage: ${mem_percent}%${NC}"
            check_threshold "$mem_percent" "$ALERT_THRESHOLD_MEM" "Memory usage"
        fi
        draw_line
    fi

    # Storage Information with alerts
    if [ "$QUIET_MODE" = false ]; then
        echo -e "${BLUE}${BOLD}💽 Storage Information:${NC}"
        echo -e "${CYAN}$(get_storage_usage)${NC}"
        
        # Disk threshold check
        local disk_percent=$(get_disk_percentage)
        if [ "$ENABLE_ALERTS" = true ]; then
            check_threshold "$disk_percent" "$ALERT_THRESHOLD_DISK" "Disk usage"
        fi
        
        if [ "$DETAILED_MODE" = true ]; then
            check_disk_health
        fi
        draw_line
    fi

    # Process Information (detailed mode)
    if [ "$DETAILED_MODE" = true ] && [ "$QUIET_MODE" = false ]; then
        get_process_info
        draw_line
    fi

    # Services Status
    if [ "$QUIET_MODE" = false ]; then
        echo -e "${BLUE}${BOLD}🔧 Important Services:${NC}"
        check_service ssh
        check_service firewall
        check_service apache2
        check_service nginx
        check_service mysql
        check_service postgresql
        
        if [ "$DETAILED_MODE" = true ]; then
            check_docker_containers
        fi
        draw_line
    fi

    # Network Information
    if [ "$QUIET_MODE" = false ]; then
        echo -e "${BLUE}${BOLD}🌐 Network Information:${NC}"
        echo -e "${CYAN}IP Addresses:${NC}"
        for ip in $(get_ip_info); do
            echo -e "${CYAN} - $ip${NC}"
        done
        
        if [ "$DETAILED_MODE" = true ]; then
            echo -e "${BLUE}${BOLD}Network Configuration:${NC}"
            echo -e "${CYAN}$(get_network_config | head -20)${NC}"
        fi
        draw_line
    fi

    # Network Services
    if [ "$QUIET_MODE" = false ]; then
        check_network_services
        draw_line
    fi

    # Security Status (detailed mode)
    if [ "$DETAILED_MODE" = true ] && [ "$QUIET_MODE" = false ]; then
        check_security_status
        draw_line
    fi

    # System Updates
    if [ "$DETAILED_MODE" = true ] && [ "$QUIET_MODE" = false ]; then
        check_system_updates
        draw_line
    fi

    # Summary
    if [ "$QUIET_MODE" = false ]; then
        local report_end_time=$(date +%s)
        local report_duration=$((report_end_time - REPORT_START_TIME))
        
        echo -e "${BLUE}${BOLD}📈 Report Summary:${NC}"
        echo -e "${CYAN}Warnings: $TOTAL_WARNINGS${NC}"
        echo -e "${CYAN}Errors: $TOTAL_ERRORS${NC}"
        echo -e "${CYAN}Report Duration: ${report_duration}s${NC}"
        
        if [ "$TOTAL_WARNINGS" -gt 0 ] || [ "$TOTAL_ERRORS" -gt 0 ]; then
            echo -e "${YELLOW}⚠️  Check log file for details: $LOG_FILE${NC}"
        fi
        
        draw_line
        echo -e "${MAGENTA}${BOLD}End of Report${NC}"
    fi
    
    log_message "Server report completed. Warnings: $TOTAL_WARNINGS, Errors: $TOTAL_ERRORS"
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
                monitoring_mode
                exit 0
                ;;
            --report-only)
                QUIET_MODE=true
                ENABLE_EXPORT=true
                shift
                ;;
            --security-scan)
                run_security_scan
                exit 0
                ;;
            --performance-test)
                run_performance_tests
                exit 0
                ;;
            --health-check)
                check_system_health
                exit 0
                ;;
            --email-test)
                test_email_config
                exit 0
                ;;
            --recommendations)
                generate_health_recommendations
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main execution
main() {
    # Check dependencies
    if ! command -v bc &>/dev/null; then
        echo -e "${YELLOW}Warning: 'bc' command not found. Some calculations may not work.${NC}"
    fi
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Run main report
    main_report
    
    # Export if requested
    if [ "$ENABLE_EXPORT" = true ] && [ -n "$OUTPUT_FILE" ]; then
        case "${EXPORT_FORMAT:-txt}" in
            json)
                generate_json_report "$OUTPUT_FILE"
                echo -e "${GREEN}Report exported to: $OUTPUT_FILE (JSON format)${NC}"
                ;;
            txt)
                main_report > "$OUTPUT_FILE" 2>&1
                echo -e "${GREEN}Report exported to: $OUTPUT_FILE (TXT format)${NC}"
                ;;
            html)
                generate_html_report "$OUTPUT_FILE"
                ;;
            *)
                echo -e "${RED}Unsupported export format: $EXPORT_FORMAT${NC}"
                exit 1
                ;;
        esac
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# ...existing code...

# Source additional modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/security_scanner.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/performance_benchmark.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/html_generator.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/email_notifications.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/health_checker.sh" 2>/dev/null || true

# Advanced system analysis functions
get_cpu_temperature() {
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then
        if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
            local temp=$(cat /sys/class/thermal/thermal_zone0/temp)
            echo "$((temp / 1000))°C"
        elif command -v sensors &>/dev/null; then
            sensors | grep -i "Package id 0" | awk '{print $4}' | head -1
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

get_load_average() {
    local os=$(get_os)
    if [ "$os" == "Linux" ] || [ "$os" == "Mac" ]; then
        uptime | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//'
    else
        echo "N/A"
    fi
}

get_uptime_info() {
    uptime -p 2>/dev/null || uptime | sed 's/^[^,]*up *//' | sed 's/,.*$//'
}

get_memory_percentage() {
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then
        free | awk 'NR==2{printf "%.1f", $3*100/$2}'
    else
        echo "N/A"
    fi
}

get_disk_percentage() {
    df / | awk 'NR==2{print $5}' | sed 's/%//'
}

get_load_average() {
    local os=$(get_os)
    if [ "$os" == "Linux" ] || [ "$os" == "Mac" ]; then
        uptime | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//'
    else
        echo "N/A"
    fi
}

get_uptime_info() {
    uptime -p 2>/dev/null || uptime | sed 's/^[^,]*up *//' | sed 's/,.*$//'
}

check_disk_health() {
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then
        if command -v smartctl &>/dev/null; then
            echo -e "${BLUE}${BOLD}SMART Disk Health:${NC}"
            for disk in $(lsblk -d -n -o name | grep -E '^sd|^nvme'); do
                local health=$(smartctl -H /dev/$disk 2>/dev/null | grep "SMART overall-health" | awk '{print $6}')
                if [ "$health" == "PASSED" ]; then
                    echo -e "${GREEN}/dev/$disk: $health${NC}"
                else
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
    ps aux --sort=-%cpu | head -6 | tail -5 | awk '{printf "%-8s %-6s %-6s %s\n", $1, $2, $3, $11}'
    
    echo -e "\n${BLUE}${BOLD}Top 5 Memory-consuming processes:${NC}"
    ps aux --sort=-%mem | head -6 | tail -5 | awk '{printf "%-8s %-6s %-6s %s\n", $1, $2, $4, $11}'
}

check_security_status() {
    local os=$(get_os)
    echo -e "${BLUE}${BOLD}Security Status:${NC}"
    
    # Check for failed login attempts
    if [ "$os" == "Linux" ]; then
        local failed_logins=$(journalctl -u ssh --since "24 hours ago" 2>/dev/null | grep -c "Failed password" || echo "0")
        if [ "$failed_logins" -gt 10 ]; then
            echo -e "${RED}⚠️  High number of failed SSH login attempts: $failed_logins${NC}"
            ((TOTAL_WARNINGS++))
        else
            echo -e "${GREEN}✓ SSH login attempts normal: $failed_logins${NC}"
        fi
        
        # Check for root login attempts
        local root_attempts=$(last root 2>/dev/null | wc -l)
        if [ "$root_attempts" -gt 0 ]; then
            echo -e "${YELLOW}⚠️  Recent root login attempts detected${NC}"
        fi
        
        # Check open ports
        if command -v ss &>/dev/null; then
            local open_ports=$(ss -tuln | grep LISTEN | wc -l)
            echo -e "${CYAN}Open listening ports: $open_ports${NC}"
        fi
    fi
}

check_system_updates() {
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then
        if command -v apt &>/dev/null; then
            echo -e "${BLUE}${BOLD}Package Updates (APT):${NC}"
            local updates=$(apt list --upgradable 2>/dev/null | wc -l)
            if [ "$updates" -gt 1 ]; then
                echo -e "${YELLOW}Available updates: $((updates - 1))${NC}"
            else
                echo -e "${GREEN}System is up to date${NC}"
            fi
        elif command -v yum &>/dev/null; then
            echo -e "${BLUE}${BOLD}Package Updates (YUM):${NC}"
            local updates=$(yum check-update 2>/dev/null | grep -c "^[a-zA-Z]" || echo "0")
            if [ "$updates" -gt 0 ]; then
                echo -e "${YELLOW}Available updates: $updates${NC}"
            else
                echo -e "${GREEN}System is up to date${NC}"
            fi
        fi
    fi
}

get_memory_percentage() {
    local os=$(get_os)
    if [ "$os" == "Linux" ]; then
        free | awk 'NR==2{printf "%.1f", $3*100/$2}'
    else
        echo "N/A"
    fi
}

get_disk_percentage() {
    df / | awk 'NR==2{print $5}' | sed 's/%//'
}

check_docker_containers() {
    if command -v docker &>/dev/null; then
        echo -e "${BLUE}${BOLD}Docker Containers:${NC}"
        local running=$(docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | tail -n +2 | wc -l)
        local total=$(docker ps -a --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | tail -n +2 | wc -l)
        echo -e "${CYAN}Running: $running | Total: $total${NC}"
        
        if [ "$DETAILED_MODE" = true ]; then
            docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null
        fi
    fi
}

check_security_status() {
    local os=$(get_os)
    echo -e "${BLUE}${BOLD}🔒 Security Status:${NC}"
    
    # Check for failed login attempts
    if [ "$os" == "Linux" ]; then
        if command -v journalctl &>/dev/null; then
            local failed_logins=$(journalctl -u ssh --since "24 hours ago" 2>/dev/null | grep -c "Failed password" || echo "0")
            if [ "$failed_logins" -gt 10 ]; then
                echo -e "${RED}⚠️  High number of failed SSH login attempts: $failed_logins${NC}"
                ((TOTAL_WARNINGS++))
            else
                echo -e "${GREEN}✓ SSH login attempts normal: $failed_logins${NC}"
            fi
        fi
        
        # Check for root login attempts
        local root_attempts=$(last root 2>/dev/null | wc -l)
        if [ "$root_attempts" -gt 0 ]; then
            echo -e "${YELLOW}⚠️  Recent root login attempts detected${NC}"
        fi
        
        # Check open ports
        if command -v ss &>/dev/null; then
            local open_ports=$(ss -tuln | grep LISTEN | wc -l)
            echo -e "${CYAN}Open listening ports: $open_ports${NC}"
        elif command -v netstat &>/dev/null; then
            local open_ports=$(netstat -tuln | grep LISTEN | wc -l)
            echo -e "${CYAN}Open listening ports: $open_ports${NC}"
        fi
    fi
}

check_system_updates() {
    local os=$(get_os)
    echo -e "${BLUE}${BOLD}📦 System Updates:${NC}"
    
    if [ "$os" == "Linux" ]; then
        if command -v apt &>/dev/null; then
            echo -e "${BLUE}${BOLD}Package Updates (APT):${NC}"
            local updates=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")
            if [ "$updates" -gt 1 ]; then
                echo -e "${YELLOW}Available updates: $((updates - 1))${NC}"
            else
                echo -e "${GREEN}System is up to date${NC}"
            fi
        elif command -v yum &>/dev/null; then
            echo -e "${BLUE}${BOLD}Package Updates (YUM):${NC}"
            local updates=$(yum check-update 2>/dev/null | grep -c "^[a-zA-Z]" || echo "0")
            if [ "$updates" -gt 0 ]; then
                echo -e "${YELLOW}Available updates: $updates${NC}"
            else
                echo -e "${GREEN}System is up to date${NC}"
            fi
        elif command -v dnf &>/dev/null; then
            echo -e "${BLUE}${BOLD}Package Updates (DNF):${NC}"
            local updates=$(dnf check-update 2>/dev/null | grep -c "^[a-zA-Z]" || echo "0")
            if [ "$updates" -gt 0 ]; then
                echo -e "${YELLOW}Available updates: $updates${NC}"
            else
                echo -e "${GREEN}System is up to date${NC}"
            fi
        else
            echo -e "${YELLOW}Package manager not found${NC}"
        fi
    elif [ "$os" == "Mac" ]; then
        echo -e "${BLUE}${BOLD}Software Updates (macOS):${NC}"
        if command -v softwareupdate &>/dev/null; then
            local updates=$(softwareupdate -l 2>/dev/null | grep -c "recommended" || echo "0")
            if [ "$updates" -gt 0 ]; then
                echo -e "${YELLOW}Available updates: $updates${NC}"
            else
                echo -e "${GREEN}System is up to date${NC}"
            fi
        fi
    fi
}

generate_json_report() {
    local output_file="$1"
    local cpu_usage=$(parse_cpu_percentage "$(get_cpu_usage)")
    local mem_percentage=$(get_memory_percentage)
    local disk_percentage=$(get_disk_percentage)
    
    cat > "$output_file" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "system": {
        "os": "$(uname -srm)",
        "uptime": "$(get_uptime_info)",
        "load_average": "$(get_load_average)"
    },
    "cpu": {
        "cores": $(get_cpu_count),
        "usage_percent": $cpu_usage,
        "temperature": "$(get_cpu_temperature)"
    },
    "memory": {
        "usage_percent": $mem_percentage,
        "details": "$(get_memory_usage)"
    },
    "storage": {
        "root_usage_percent": $disk_percentage,
        "details": "$(get_storage_usage | tail -1)"
    },
    "network": {
        "ip_addresses": [$(get_ip_info | sed 's/^/"/' | sed 's/$/"/' | tr '\n' ',' | sed 's/,$/\n/')]
    },
    "alerts": {
        "warnings": $TOTAL_WARNINGS,
        "errors": $TOTAL_ERRORS
    }
}
EOF
}

monitoring_mode() {
    echo -e "${MAGENTA}${BOLD}Starting continuous monitoring mode...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    
    while true; do
        clear
        main_report
        echo -e "\n${DIM}Refreshing in 30 seconds...${NC}"
        sleep 30
    done
}
