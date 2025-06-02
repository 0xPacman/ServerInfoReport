#!/bin/bash

# System Health Checker - Comprehensive system diagnostics

check_system_health() {
    echo -e "${MAGENTA}${BOLD}🏥 SYSTEM HEALTH CHECK${NC}"
    echo -e "${MAGENTA}${BOLD}====================${NC}"
    
    local health_score=100
    local critical_issues=0
    local warnings=0
    
    # Check CPU health
    echo -e "${BLUE}${BOLD}🖥️  CPU Health Check:${NC}"
    local cpu_usage_num=$(parse_cpu_percentage "$(get_cpu_usage)" 2>/dev/null || echo "0")
    if [ -n "$cpu_usage_num" ] && command -v bc &>/dev/null; then
        if (( $(echo "$cpu_usage_num > 90" | bc -l) )); then
            echo -e "${RED}❌ CPU usage critically high: ${cpu_usage_num}%${NC}"
            ((critical_issues++))
            health_score=$((health_score - 20))
        elif (( $(echo "$cpu_usage_num > 80" | bc -l) )); then
            echo -e "${YELLOW}⚠️  CPU usage high: ${cpu_usage_num}%${NC}"
            ((warnings++))
            health_score=$((health_score - 10))
        else
            echo -e "${GREEN}✓ CPU usage normal: ${cpu_usage_num}%${NC}"
        fi
    fi
    
    # Check CPU temperature
    local cpu_temp=$(get_cpu_temperature 2>/dev/null)
    if [[ "$cpu_temp" =~ ^[0-9]+°C$ ]]; then
        local temp_num=$(echo "$cpu_temp" | grep -oE '[0-9]+')
        if [ "$temp_num" -gt 80 ]; then
            echo -e "${RED}❌ CPU temperature critical: $cpu_temp${NC}"
            ((critical_issues++))
            health_score=$((health_score - 15))
        elif [ "$temp_num" -gt 70 ]; then
            echo -e "${YELLOW}⚠️  CPU temperature high: $cpu_temp${NC}"
            ((warnings++))
            health_score=$((health_score - 5))
        else
            echo -e "${GREEN}✓ CPU temperature normal: $cpu_temp${NC}"
        fi
    fi
    
    echo ""
    
    # Check Memory health
    echo -e "${BLUE}${BOLD}💾 Memory Health Check:${NC}"
    local mem_percent=$(get_memory_percentage 2>/dev/null || echo "0")
    if [ -n "$mem_percent" ] && command -v bc &>/dev/null; then
        if (( $(echo "$mem_percent > 95" | bc -l) )); then
            echo -e "${RED}❌ Memory usage critically high: ${mem_percent}%${NC}"
            ((critical_issues++))
            health_score=$((health_score - 20))
        elif (( $(echo "$mem_percent > 85" | bc -l) )); then
            echo -e "${YELLOW}⚠️  Memory usage high: ${mem_percent}%${NC}"
            ((warnings++))
            health_score=$((health_score - 10))
        else
            echo -e "${GREEN}✓ Memory usage normal: ${mem_percent}%${NC}"
        fi
    fi
    
    # Check for memory leaks (processes using excessive memory)
    local high_mem_processes=$(ps aux --sort=-%mem | head -6 | tail -5 | awk '$4 > 20 {print $11 " (" $4 "%)"}')
    if [ -n "$high_mem_processes" ]; then
        echo -e "${YELLOW}⚠️  High memory usage processes detected:${NC}"
        echo "$high_mem_processes" | while read line; do
            echo -e "${CYAN}  - $line${NC}"
        done
        ((warnings++))
        health_score=$((health_score - 5))
    fi
    
    echo ""
    
    # Check Disk health
    echo -e "${BLUE}${BOLD}💽 Storage Health Check:${NC}"
    local disk_percent=$(get_disk_percentage 2>/dev/null || echo "0")
    if [ -n "$disk_percent" ]; then
        if [ "$disk_percent" -gt 95 ]; then
            echo -e "${RED}❌ Disk usage critically high: ${disk_percent}%${NC}"
            ((critical_issues++))
            health_score=$((health_score - 20))
        elif [ "$disk_percent" -gt 85 ]; then
            echo -e "${YELLOW}⚠️  Disk usage high: ${disk_percent}%${NC}"
            ((warnings++))
            health_score=$((health_score - 10))
        else
            echo -e "${GREEN}✓ Disk usage normal: ${disk_percent}%${NC}"
        fi
    fi
    
    # Check for large log files
    local large_logs=$(find /var/log -name "*.log" -size +100M 2>/dev/null | wc -l)
    if [ "$large_logs" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  $large_logs large log file(s) found (>100MB)${NC}"
        ((warnings++))
        health_score=$((health_score - 5))
    fi
    
    # Check inode usage
    local inode_usage=$(df -i / | awk 'NR==2 {print $5}' | sed 's/%//' 2>/dev/null || echo "0")
    if [ "$inode_usage" -gt 90 ]; then
        echo -e "${RED}❌ Inode usage critically high: ${inode_usage}%${NC}"
        ((critical_issues++))
        health_score=$((health_score - 15))
    elif [ "$inode_usage" -gt 80 ]; then
        echo -e "${YELLOW}⚠️  Inode usage high: ${inode_usage}%${NC}"
        ((warnings++))
        health_score=$((health_score - 5))
    fi
    
    echo ""
    
    # Check Network health
    echo -e "${BLUE}${BOLD}🌐 Network Health Check:${NC}"
    
    # Check if we can resolve DNS
    if nslookup google.com >/dev/null 2>&1; then
        echo -e "${GREEN}✓ DNS resolution working${NC}"
    else
        echo -e "${RED}❌ DNS resolution failed${NC}"
        ((critical_issues++))
        health_score=$((health_score - 15))
    fi
    
    # Check internet connectivity
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Internet connectivity working${NC}"
    else
        echo -e "${YELLOW}⚠️  Internet connectivity issues${NC}"
        ((warnings++))
        health_score=$((health_score - 10))
    fi
    
    # Check network interface status
    local down_interfaces=$(ip link show | grep "state DOWN" | wc -l)
    if [ "$down_interfaces" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  $down_interfaces network interface(s) down${NC}"
        ((warnings++))
        health_score=$((health_score - 5))
    fi
    
    echo ""
    
    # Check System Load
    echo -e "${BLUE}${BOLD}📊 System Load Health Check:${NC}"
    local load_1min=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//' 2>/dev/null || echo "0")
    local cpu_cores=$(get_cpu_count)
    
    if command -v bc &>/dev/null && [ -n "$load_1min" ] && [ "$cpu_cores" -gt 0 ]; then
        local load_per_core=$(echo "scale=2; $load_1min / $cpu_cores" | bc)
        
        if (( $(echo "$load_per_core > 2.0" | bc -l) )); then
            echo -e "${RED}❌ System severely overloaded (load: $load_per_core per core)${NC}"
            ((critical_issues++))
            health_score=$((health_score - 20))
        elif (( $(echo "$load_per_core > 1.0" | bc -l) )); then
            echo -e "${YELLOW}⚠️  System overloaded (load: $load_per_core per core)${NC}"
            ((warnings++))
            health_score=$((health_score - 10))
        else
            echo -e "${GREEN}✓ System load normal (load: $load_per_core per core)${NC}"
        fi
    fi
    
    echo ""
    
    # Check for zombie processes
    echo -e "${BLUE}${BOLD}🧟 Process Health Check:${NC}"
    local zombie_count=$(ps aux | awk '$8 ~ /^Z/ {print $0}' | wc -l)
    if [ "$zombie_count" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  $zombie_count zombie process(es) detected${NC}"
        ((warnings++))
        health_score=$((health_score - 5))
    else
        echo -e "${GREEN}✓ No zombie processes${NC}"
    fi
    
    # Check for too many processes
    local total_processes=$(ps aux | wc -l)
    if [ "$total_processes" -gt 1000 ]; then
        echo -e "${YELLOW}⚠️  High number of processes: $total_processes${NC}"
        ((warnings++))
        health_score=$((health_score - 5))
    fi
    
    echo ""
    
    # Check System Services
    echo -e "${BLUE}${BOLD}🔧 Critical Services Health Check:${NC}"
    local critical_services="ssh cron rsyslog"
    local down_services=0
    
    for service in $critical_services; do
        if command -v systemctl &>/dev/null; then
            if ! systemctl is-active "$service" >/dev/null 2>&1; then
                echo -e "${YELLOW}⚠️  Service $service is not running${NC}"
                ((down_services++))
                ((warnings++))
            fi
        fi
    done
    
    if [ "$down_services" -eq 0 ]; then
        echo -e "${GREEN}✓ All critical services running${NC}"
    else
        health_score=$((health_score - (down_services * 5)))
    fi
    
    echo ""
    
    # Final Health Score
    echo -e "${BLUE}${BOLD}📋 Health Score Summary:${NC}"
    
    local health_color=""
    local health_status=""
    
    if [ "$health_score" -ge 90 ]; then
        health_color="${GREEN}"
        health_status="Excellent"
    elif [ "$health_score" -ge 75 ]; then
        health_color="${CYAN}"
        health_status="Good"
    elif [ "$health_score" -ge 60 ]; then
        health_color="${YELLOW}"
        health_status="Fair"
    elif [ "$health_score" -ge 40 ]; then
        health_color="${YELLOW}"
        health_status="Poor"
    else
        health_color="${RED}"
        health_status="Critical"
    fi
    
    echo -e "${health_color}${BOLD}Overall Health Score: $health_score/100 ($health_status)${NC}"
    echo -e "${CYAN}Critical Issues: $critical_issues${NC}"
    echo -e "${CYAN}Warnings: $warnings${NC}"
    
    if [ "$critical_issues" -gt 0 ]; then
        echo -e "${RED}${BOLD}⚠️  IMMEDIATE ATTENTION REQUIRED${NC}"
    elif [ "$warnings" -gt 5 ]; then
        echo -e "${YELLOW}${BOLD}⚠️  Multiple issues detected - review recommended${NC}"
    fi
    
    echo ""
    echo -e "${MAGENTA}${BOLD}System Health Check Complete${NC}"
    
    # Update global counters
    TOTAL_WARNINGS=$((TOTAL_WARNINGS + warnings))
    TOTAL_ERRORS=$((TOTAL_ERRORS + critical_issues))
    
    return $critical_issues
}

generate_health_recommendations() {
    echo -e "${BLUE}${BOLD}💡 System Health Recommendations:${NC}"
    
    local cpu_usage=$(parse_cpu_percentage "$(get_cpu_usage)" 2>/dev/null || echo "0")
    local mem_percent=$(get_memory_percentage 2>/dev/null || echo "0")
    local disk_percent=$(get_disk_percentage 2>/dev/null || echo "0")
    
    # CPU recommendations
    if command -v bc &>/dev/null && [ -n "$cpu_usage" ]; then
        if (( $(echo "$cpu_usage > 80" | bc -l) )); then
            echo -e "${YELLOW}📈 CPU Usage High:${NC}"
            echo -e "${CYAN}  • Check for CPU-intensive processes: top -o %CPU${NC}"
            echo -e "${CYAN}  • Consider upgrading CPU or optimizing applications${NC}"
            echo -e "${CYAN}  • Review and terminate unnecessary processes${NC}"
        fi
    fi
    
    # Memory recommendations
    if command -v bc &>/dev/null && [ -n "$mem_percent" ]; then
        if (( $(echo "$mem_percent > 85" | bc -l) )); then
            echo -e "${YELLOW}💾 Memory Usage High:${NC}"
            echo -e "${CYAN}  • Identify memory-hungry processes: ps aux --sort=-%mem${NC}"
            echo -e "${CYAN}  • Consider adding more RAM${NC}"
            echo -e "${CYAN}  • Review application memory leaks${NC}"
            echo -e "${CYAN}  • Clear system caches: sync && echo 3 > /proc/sys/vm/drop_caches${NC}"
        fi
    fi
    
    # Disk recommendations
    if [ -n "$disk_percent" ] && [ "$disk_percent" -gt 85 ]; then
        echo -e "${YELLOW}💽 Disk Usage High:${NC}"
        echo -e "${CYAN}  • Find large files: find / -type f -size +100M 2>/dev/null${NC}"
        echo -e "${CYAN}  • Clean log files: journalctl --vacuum-time=7d${NC}"
        echo -e "${CYAN}  • Remove unnecessary packages: apt autoremove${NC}"
        echo -e "${CYAN}  • Check for core dumps: find /tmp /var/tmp -name 'core*'${NC}"
    fi
    
    # General recommendations
    echo -e "${YELLOW}🔧 General Maintenance:${NC}"
    echo -e "${CYAN}  • Update system packages regularly${NC}"
    echo -e "${CYAN}  • Monitor logs for errors: journalctl -p err${NC}"
    echo -e "${CYAN}  • Backup important data${NC}"
    echo -e "${CYAN}  • Review security settings periodically${NC}"
    echo -e "${CYAN}  • Set up automated monitoring${NC}"
}
