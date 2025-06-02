#!/bin/bash

# Security Scanner Module for Advanced Server Report
# Scans for common security vulnerabilities and misconfigurations

scan_open_ports() {
    echo -e "${BLUE}${BOLD}🔍 Open Port Scan:${NC}"
    
    if command -v netstat &>/dev/null; then
        local open_ports=$(netstat -tuln | grep LISTEN | awk '{print $4}' | sed 's/.*://' | sort -n | uniq)
        local port_count=$(echo "$open_ports" | wc -l)
        
        echo -e "${CYAN}Total listening ports: $port_count${NC}"
        
        # Check for commonly vulnerable ports
        local vulnerable_ports="21 23 25 53 135 139 445 1433 3306 3389 5432"
        for port in $vulnerable_ports; do
            if echo "$open_ports" | grep -q "^$port$"; then
                case $port in
                    21) echo -e "${YELLOW}⚠️  FTP (21) - Consider using SFTP instead${NC}" ;;
                    23) echo -e "${RED}❌ Telnet (23) - Unencrypted, use SSH instead${NC}" ;;
                    25) echo -e "${YELLOW}⚠️  SMTP (25) - Ensure proper authentication${NC}" ;;
                    135|139|445) echo -e "${YELLOW}⚠️  SMB/NetBIOS ($port) - Windows file sharing${NC}" ;;
                    1433) echo -e "${YELLOW}⚠️  SQL Server (1433) - Database exposed${NC}" ;;
                    3306) echo -e "${YELLOW}⚠️  MySQL (3306) - Database exposed${NC}" ;;
                    3389) echo -e "${YELLOW}⚠️  RDP (3389) - Remote desktop exposed${NC}" ;;
                    5432) echo -e "${YELLOW}⚠️  PostgreSQL (5432) - Database exposed${NC}" ;;
                esac
                ((TOTAL_WARNINGS++))
            fi
        done
        
        if [ "$DETAILED_MODE" = true ]; then
            echo -e "${CYAN}All listening ports:${NC}"
            echo "$open_ports" | head -20
        fi
    else
        echo -e "${YELLOW}netstat not available for port scanning${NC}"
    fi
}

check_file_permissions() {
    echo -e "${BLUE}${BOLD}🔒 Critical File Permissions:${NC}"
    
    # Check sensitive files
    local sensitive_files="/etc/passwd /etc/shadow /etc/sudoers /root/.ssh/authorized_keys"
    
    for file in $sensitive_files; do
        if [ -f "$file" ]; then
            local perms=$(stat -c "%a" "$file" 2>/dev/null)
            local owner=$(stat -c "%U" "$file" 2>/dev/null)
            
            case "$file" in
                "/etc/passwd")
                    if [ "$perms" != "644" ]; then
                        echo -e "${YELLOW}⚠️  /etc/passwd has unusual permissions: $perms${NC}"
                        ((TOTAL_WARNINGS++))
                    fi
                    ;;
                "/etc/shadow")
                    if [ "$perms" != "640" ] && [ "$perms" != "600" ]; then
                        echo -e "${RED}❌ /etc/shadow has insecure permissions: $perms${NC}"
                        ((TOTAL_ERRORS++))
                    fi
                    ;;
                "/etc/sudoers")
                    if [ "$perms" != "440" ]; then
                        echo -e "${YELLOW}⚠️  /etc/sudoers has unusual permissions: $perms${NC}"
                        ((TOTAL_WARNINGS++))
                    fi
                    ;;
            esac
        fi
    done
}

check_ssh_config() {
    echo -e "${BLUE}${BOLD}🔑 SSH Configuration Security:${NC}"
    
    local ssh_config="/etc/ssh/sshd_config"
    if [ -f "$ssh_config" ]; then
        # Check for root login
        if grep -q "^PermitRootLogin yes" "$ssh_config"; then
            echo -e "${RED}❌ Root login is enabled${NC}"
            ((TOTAL_ERRORS++))
        elif grep -q "^PermitRootLogin" "$ssh_config"; then
            echo -e "${GREEN}✓ Root login is restricted${NC}"
        fi
        
        # Check for password authentication
        if grep -q "^PasswordAuthentication yes" "$ssh_config"; then
            echo -e "${YELLOW}⚠️  Password authentication is enabled${NC}"
            ((TOTAL_WARNINGS++))
        elif grep -q "^PasswordAuthentication no" "$ssh_config"; then
            echo -e "${GREEN}✓ Password authentication is disabled${NC}"
        fi
        
        # Check SSH protocol
        if grep -q "^Protocol 1" "$ssh_config"; then
            echo -e "${RED}❌ SSH Protocol 1 is enabled (insecure)${NC}"
            ((TOTAL_ERRORS++))
        fi
        
        # Check for key-based authentication
        if grep -q "^PubkeyAuthentication yes" "$ssh_config"; then
            echo -e "${GREEN}✓ Public key authentication is enabled${NC}"
        fi
    else
        echo -e "${YELLOW}SSH configuration file not found${NC}"
    fi
}

check_user_accounts() {
    echo -e "${BLUE}${BOLD}👥 User Account Security:${NC}"
    
    # Check for accounts with empty passwords
    local empty_pass=$(awk -F: '($2 == "") {print $1}' /etc/shadow 2>/dev/null | wc -l)
    if [ "$empty_pass" -gt 0 ]; then
        echo -e "${RED}❌ $empty_pass account(s) with empty passwords found${NC}"
        ((TOTAL_ERRORS++))
    else
        echo -e "${GREEN}✓ No accounts with empty passwords${NC}"
    fi
    
    # Check for duplicate UIDs
    local dup_uids=$(awk -F: '{print $3}' /etc/passwd | sort -n | uniq -d | wc -l)
    if [ "$dup_uids" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  $dup_uids duplicate UID(s) found${NC}"
        ((TOTAL_WARNINGS++))
    fi
    
    # Check for users with UID 0 (should only be root)
    local uid_zero=$(awk -F: '($3 == 0) {print $1}' /etc/passwd | grep -v "^root$" | wc -l)
    if [ "$uid_zero" -gt 0 ]; then
        echo -e "${RED}❌ Non-root users with UID 0 found${NC}"
        ((TOTAL_ERRORS++))
    fi
    
    # Show recently logged in users
    if command -v last &>/dev/null; then
        echo -e "${CYAN}Recent logins (last 5):${NC}"
        last -n 5 | head -5
    fi
}

check_system_integrity() {
    echo -e "${BLUE}${BOLD}🛡️  System Integrity:${NC}"
    
    # Check for suspicious processes
    local suspicious_processes=$(ps aux | grep -E "(nc|netcat|ncat)" | grep -v grep | wc -l)
    if [ "$suspicious_processes" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Suspicious network tools detected: $suspicious_processes${NC}"
        ((TOTAL_WARNINGS++))
    fi
    
    # Check for core dumps
    local core_dumps=$(find /tmp /var/tmp /home -name "core*" -type f 2>/dev/null | wc -l)
    if [ "$core_dumps" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  $core_dumps core dump(s) found${NC}"
        ((TOTAL_WARNINGS++))
    fi
    
    # Check system file modifications (if possible)
    if command -v rpm &>/dev/null; then
        local modified_files=$(rpm -Va 2>/dev/null | wc -l)
        if [ "$modified_files" -gt 0 ]; then
            echo -e "${YELLOW}⚠️  $modified_files system files have been modified${NC}"
        fi
    fi
}

run_security_scan() {
    echo -e "${MAGENTA}${BOLD}🔐 SECURITY SCAN REPORT${NC}"
    echo -e "${MAGENTA}${BOLD}=====================${NC}"
    
    scan_open_ports
    echo ""
    check_file_permissions
    echo ""
    check_ssh_config
    echo ""
    check_user_accounts
    echo ""
    check_system_integrity
    echo ""
    
    echo -e "${MAGENTA}${BOLD}Security Scan Complete${NC}"
    echo -e "${CYAN}Warnings: $TOTAL_WARNINGS | Errors: $TOTAL_ERRORS${NC}"
}
