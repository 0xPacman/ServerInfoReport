#!/bin/bash

# Performance Benchmarker for Server Report
# Runs basic performance tests and benchmarks

run_cpu_benchmark() {
    echo -e "${BLUE}${BOLD}🏃‍♂️ CPU Performance Test:${NC}"
    
    if command -v bc &>/dev/null; then
        local start_time=$(date +%s.%N)
        
        # Simple CPU benchmark - calculate pi
        echo "scale=1000; 4*a(1)" | bc -l > /dev/null 2>&1
        
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)
        
        echo -e "${CYAN}Pi calculation time: ${duration}s${NC}"
        
        if (( $(echo "$duration > 2.0" | bc -l) )); then
            echo -e "${YELLOW}⚠️  CPU performance may be degraded${NC}"
            ((TOTAL_WARNINGS++))
        else
            echo -e "${GREEN}✓ CPU performance normal${NC}"
        fi
    else
        echo -e "${YELLOW}bc not available for CPU benchmark${NC}"
    fi
}

run_memory_benchmark() {
    echo -e "${BLUE}${BOLD}💾 Memory Performance Test:${NC}"
    
    local start_time=$(date +%s.%N)
    
    # Memory allocation test
    dd if=/dev/zero of=/tmp/memtest bs=1M count=100 2>/dev/null
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null)
    
    if [ -n "$duration" ]; then
        echo -e "${CYAN}Memory write test (100MB): ${duration}s${NC}"
        local speed=$(echo "scale=2; 100 / $duration" | bc 2>/dev/null)
        echo -e "${CYAN}Write speed: ${speed} MB/s${NC}"
    fi
    
    # Cleanup
    rm -f /tmp/memtest
}

run_disk_benchmark() {
    echo -e "${BLUE}${BOLD}💽 Disk I/O Performance Test:${NC}"
    
    local test_file="/tmp/disktest_$$"
    
    # Write test
    echo -e "${CYAN}Running disk write test...${NC}"
    local write_start=$(date +%s.%N)
    dd if=/dev/zero of="$test_file" bs=1M count=100 conv=fsync 2>/dev/null
    local write_end=$(date +%s.%N)
    
    if command -v bc &>/dev/null; then
        local write_time=$(echo "$write_end - $write_start" | bc)
        local write_speed=$(echo "scale=2; 100 / $write_time" | bc)
        echo -e "${CYAN}Write speed: ${write_speed} MB/s${NC}"
    fi
    
    # Read test
    echo -e "${CYAN}Running disk read test...${NC}"
    local read_start=$(date +%s.%N)
    dd if="$test_file" of=/dev/null bs=1M 2>/dev/null
    local read_end=$(date +%s.%N)
    
    if command -v bc &>/dev/null; then
        local read_time=$(echo "$read_end - $read_start" | bc)
        local read_speed=$(echo "scale=2; 100 / $read_time" | bc)
        echo -e "${CYAN}Read speed: ${read_speed} MB/s${NC}"
        
        # Performance warnings
        if (( $(echo "$write_speed < 10" | bc -l) )); then
            echo -e "${YELLOW}⚠️  Slow disk write performance${NC}"
            ((TOTAL_WARNINGS++))
        fi
        
        if (( $(echo "$read_speed < 50" | bc -l) )); then
            echo -e "${YELLOW}⚠️  Slow disk read performance${NC}"
            ((TOTAL_WARNINGS++))
        fi
    fi
    
    # Cleanup
    rm -f "$test_file"
}

run_network_test() {
    echo -e "${BLUE}${BOLD}🌐 Network Connectivity Test:${NC}"
    
    # Test DNS resolution
    if nslookup google.com > /dev/null 2>&1; then
        echo -e "${GREEN}✓ DNS resolution working${NC}"
    else
        echo -e "${RED}❌ DNS resolution failed${NC}"
        ((TOTAL_ERRORS++))
    fi
    
    # Test internet connectivity
    if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Internet connectivity working${NC}"
    else
        echo -e "${YELLOW}⚠️  Internet connectivity issues${NC}"
        ((TOTAL_WARNINGS++))
    fi
    
    # Test local network
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    if [ -n "$gateway" ] && ping -c 1 "$gateway" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Local network connectivity working${NC}"
    else
        echo -e "${YELLOW}⚠️  Local network connectivity issues${NC}"
        ((TOTAL_WARNINGS++))
    fi
}

check_system_load() {
    echo -e "${BLUE}${BOLD}📊 System Load Analysis:${NC}"
    
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_cores=$(nproc 2>/dev/null || echo "1")
    
    if command -v bc &>/dev/null; then
        local load_per_core=$(echo "scale=2; $load_avg / $cpu_cores" | bc)
        echo -e "${CYAN}Load average (1 min): $load_avg${NC}"
        echo -e "${CYAN}Load per core: $load_per_core${NC}"
        
        if (( $(echo "$load_per_core > 1.0" | bc -l) )); then
            echo -e "${RED}❌ System is overloaded${NC}"
            ((TOTAL_ERRORS++))
        elif (( $(echo "$load_per_core > 0.7" | bc -l) )); then
            echo -e "${YELLOW}⚠️  System load is high${NC}"
            ((TOTAL_WARNINGS++))
        else
            echo -e "${GREEN}✓ System load is normal${NC}"
        fi
    fi
}

run_performance_tests() {
    echo -e "${MAGENTA}${BOLD}🏁 PERFORMANCE BENCHMARK REPORT${NC}"
    echo -e "${MAGENTA}${BOLD}===============================${NC}"
    
    check_system_load
    echo ""
    
    run_cpu_benchmark
    echo ""
    
    run_memory_benchmark
    echo ""
    
    run_disk_benchmark
    echo ""
    
    run_network_test
    echo ""
    
    echo -e "${MAGENTA}${BOLD}Performance Tests Complete${NC}"
    echo -e "${CYAN}Warnings: $TOTAL_WARNINGS | Errors: $TOTAL_ERRORS${NC}"
}
