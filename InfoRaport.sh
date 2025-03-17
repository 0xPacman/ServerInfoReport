#!/bin/bash

NC="\033[0m"  
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
BOLD="\033[1m"


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


clear
echo -e "${MAGENTA}${BOLD}==================================================${NC}"
echo -e "${MAGENTA}${BOLD}                SERVER MONITOR REPORT             ${NC}"
echo -e "${MAGENTA}${BOLD}==================================================${NC}"
echo -e "${YELLOW}Time: $(date)${NC}"
draw_line

echo -e "${BLUE}${BOLD}System Information:${NC}"
echo -e "${CYAN}OS & Kernel: $(uname -srm)${NC}"
draw_line

echo -e "${BLUE}${BOLD}CPU Info:${NC}"
echo -e "${CYAN}Total Cores: $(get_cpu_count)${NC}"
echo -e "${CYAN}Usage: $(get_cpu_usage)${NC}"
draw_line

echo -e "${BLUE}${BOLD}Memory Info:${NC}"
echo -e "${CYAN}$(get_memory_usage)${NC}"
draw_line

echo -e "${BLUE}${BOLD}Storage (Root Partition):${NC}"
echo -e "${CYAN}$(get_storage_usage)${NC}"
draw_line

echo -e "${BLUE}${BOLD}Important Services:${NC}"
check_service ssh
check_service firewall
check_service apache2
# Add more services here if needed, e.g., check_service apache2

draw_line


echo -e "${BLUE}${BOLD}Network Info:${NC}"
echo -e "${CYAN}IP Addresses:${NC}"
for ip in $(get_ip_info); do
    echo -e "${CYAN} - $ip${NC}"
done
echo -e "${BLUE}${BOLD}Network Configuration:${NC}"
echo -e "${CYAN}$(get_network_config)${NC}"
draw_line

check_network_services
draw_line

echo -e "${MAGENTA}${BOLD}End of Report${NC}"
