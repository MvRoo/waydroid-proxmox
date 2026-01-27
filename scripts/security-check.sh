#!/usr/bin/env bash

# Security Validation Script for waydroid-proxmox
# This script checks all bash scripts in the repository for common malicious patterns
# Run this before installation to verify the scripts are safe

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# Check results tracking
declare -a ISSUES
declare -a SUSPICIOUS_PATTERNS

print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Waydroid Proxmox Security Validation${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo ""
}

print_section() {
    echo -e "\n${BLUE}▶ $1${NC}"
    echo "─────────────────────────────────────────────"
}

check_pass() {
    ((TOTAL_CHECKS++))
    ((PASSED_CHECKS++))
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    ((TOTAL_CHECKS++))
    ((FAILED_CHECKS++))
    echo -e "${RED}✗${NC} $1"
    ISSUES+=("$1")
}

check_warn() {
    ((TOTAL_CHECKS++))
    ((WARNINGS++))
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check 1: No data exfiltration attempts
check_data_exfiltration() {
    print_section "Checking for Data Exfiltration Attempts"
    
    local suspicious_urls=0
    
    # List of trusted domains
    local trusted_domains=(
        "github.com"
        "githubusercontent.com"
        "repo.waydro.id"
        "waydro.id"
        "debian.org"
        "ubuntu.com"
        "f-droid.org"
        "api.github.com"
    )
    
    # Extract all URLs from shell scripts (use -E for better compatibility)
    while IFS= read -r url; do
        local is_trusted=false
        for domain in "${trusted_domains[@]}"; do
            if [[ "$url" == *"$domain"* ]]; then
                is_trusted=true
                break
            fi
        done
        
        # Check for suspicious patterns (external IPs, uncommon TLDs, etc.)
        # Exclude localhost/bind addresses (0.0.0.0, 127.0.0.1, etc.)
        if [[ "$url" =~ ^https?://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
            # Skip localhost and bind addresses
            if [[ "$url" =~ ^https?://(0\.0\.0\.0|127\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
                continue
            fi
            if ! $is_trusted; then
                ((suspicious_urls++))
                SUSPICIOUS_PATTERNS+=("IP-based URL: $url")
            fi
        fi
    done < <(grep -rhE 'https?://[^"'\'' ]+' "$REPO_ROOT" --include="*.sh" 2>/dev/null | sort -u)
    
    if [ $suspicious_urls -eq 0 ]; then
        check_pass "No suspicious external connections found"
    else
        check_warn "Found $suspicious_urls potentially suspicious URLs (review needed)"
    fi
}

# Check 2: No dangerous system commands
check_dangerous_commands() {
    print_section "Checking for Dangerous System Commands"
    
    # Check for rm -rf with dangerous patterns (excluding safe patterns and this script)
    local dangerous_rm=$(grep -r "rm -rf /" "$REPO_ROOT" --include="*.sh" --exclude="security-check.sh" 2>/dev/null | grep -v "rm -rf /home\|rm -rf /var\|rm -rf /tmp\|rm -rf /root\|rm -rf /usr/local\|rm -rf /opt" | wc -l)
    if [ "$dangerous_rm" -eq 0 ]; then
        check_pass "No dangerous 'rm -rf /' commands found"
    else
        check_fail "Found potentially dangerous 'rm -rf' commands"
    fi
    
    # Check for dd commands that could wipe disks (excluding test/benchmark usage and this script)
    local dangerous_dd=$(grep -r "dd.*if=/dev/zero.*of=/dev/[hs]d" "$REPO_ROOT" --include="*.sh" --exclude="security-check.sh" 2>/dev/null | wc -l)
    if [ "$dangerous_dd" -eq 0 ]; then
        check_pass "No disk-wiping 'dd' commands found"
    else
        check_fail "Found potentially dangerous 'dd' commands"
    fi
    
    # Check for eval with external input (use -E for proper regex)
    local eval_count=$(grep -rEn "eval.*\$" "$REPO_ROOT" --include="*.sh" --exclude-dir="archive" --exclude-dir="test*" 2>/dev/null | grep -Ev "^[[:space:]]*#" | wc -l)
    if [ "$eval_count" -eq 0 ]; then
        check_pass "No 'eval' with variable expansion found"
    else
        check_warn "Found $eval_count 'eval' commands with variables (review recommended)"
    fi
    
    # Check for chmod 777 (overly permissive) - exclude socket/runtime dirs where it's necessary
    local chmod_777=$(grep -r "chmod 777" "$REPO_ROOT" --include="*.sh" --exclude-dir="archive" 2>/dev/null | grep -Ev "wayland|socket|runtime" | wc -l)
    if [ "$chmod_777" -eq 0 ]; then
        check_pass "No 'chmod 777' (overly permissive permissions) found"
    else
        check_warn "Found $chmod_777 'chmod 777' commands (security risk)"
    fi
}

# Check 3: No SSH/credential manipulation
check_credential_theft() {
    print_section "Checking for Credential Theft Attempts"
    
    # Check for SSH file references (use -E for \s)
    local ssh_access=$(grep -rE '\.ssh|id_rsa|authorized_keys' "$REPO_ROOT" --include="*.sh" 2>/dev/null | grep -Ev "^[[:space:]]*#" | wc -l)
    if [ "$ssh_access" -eq 0 ]; then
        check_pass "No SSH key manipulation detected"
    else
        check_warn "Found $ssh_access references to SSH files (review needed)"
    fi
    
    # Check for /etc/shadow or /etc/passwd manipulation (use -E for proper regex)
    local passwd_access=$(grep -rE "/etc/shadow|/etc/passwd" "$REPO_ROOT" --include="*.sh" --exclude="security-check.sh" 2>/dev/null | grep -Ev "^[[:space:]]*#|grep|echo|cat /etc/os-release|PRETTY_NAME" | wc -l)
    if [ "$passwd_access" -eq 0 ]; then
        check_pass "No password file manipulation detected"
    else
        check_fail "Found manipulation of /etc/shadow or /etc/passwd"
    fi
    
    # Check for credential scraping patterns (use -E for proper regex)
    local scraping=$(grep -rE "cat.*/\.bash_history|cat.*/\.mysql_history" "$REPO_ROOT" --include="*.sh" --exclude="security-check.sh" 2>/dev/null | grep -Ev "^[[:space:]]*#" | wc -l)
    if [ "$scraping" -eq 0 ]; then
        check_pass "No credential scraping patterns detected"
    else
        check_fail "Found potential credential scraping commands"
    fi
}

# Check 4: No obfuscated code
check_obfuscation() {
    print_section "Checking for Code Obfuscation"
    
    # Check for base64 encoded commands (potential malware) - excluding base64 password generation
    local base64_exec=$(grep -rE "base64.*\|.*(sh|bash)" "$REPO_ROOT" --include="*.sh" --exclude="security-check.sh" 2>/dev/null | grep -Ev "openssl rand.*base64|base64.*password|base64.*token" | wc -l)
    local base64_decode=$(grep -rE "echo.*\|.*base64.*-d.*\|.*(sh|bash)" "$REPO_ROOT" --include="*.sh" --exclude="security-check.sh" 2>/dev/null | wc -l)
    local total_suspicious=$((base64_exec + base64_decode))
    if [ "$total_suspicious" -eq 0 ]; then
        check_pass "No base64-encoded command execution found"
    else
        check_fail "Found base64-encoded command execution (obfuscation)"
    fi
    
    # Check for hex-encoded strings (properly escaped for grep -E)
    local hex_strings=$(grep -rE '\\x[0-9a-fA-F]{2}' "$REPO_ROOT" --include="*.sh" 2>/dev/null | wc -l)
    if [ "$hex_strings" -eq 0 ]; then
        check_pass "No suspicious hex-encoded strings found"
    else
        check_warn "Found $hex_strings hex-encoded strings (review recommended)"
    fi
}

# Check 5: Proper credential handling
check_credential_security() {
    print_section "Checking Credential Security Practices"
    
    # Check for secure random generation
    local secure_random=$(grep -r "openssl rand\|secrets\.token\|/dev/urandom" "$REPO_ROOT" --include="*.sh" --include="*.py" 2>/dev/null | wc -l)
    if [ "$secure_random" -gt 0 ]; then
        check_pass "Uses cryptographically secure random generation"
    else
        check_warn "No secure random generation detected"
    fi
    
    # Check for proper file permissions on sensitive files
    local chmod_600=$(grep -r "chmod 600" "$REPO_ROOT" --include="*.sh" 2>/dev/null | grep -i "password\|token\|key" | wc -l)
    if [ "$chmod_600" -gt 0 ]; then
        check_pass "Sets restrictive permissions (600) on sensitive files"
    else
        check_warn "May not set proper permissions on sensitive files"
    fi
}

# Check 6: No backdoors or persistence mechanisms
check_backdoors() {
    print_section "Checking for Backdoors and Persistence"
    
    # Check for unauthorized cron job creation (use -E for proper regex)
    local cron_mods=$(grep -rE "crontab -e" "$REPO_ROOT" --include="*.sh" 2>/dev/null | grep -Ev "^[[:space:]]*#" | grep -Evi "Example|example" | wc -l)
    local cron_writes=$(grep -rE "echo.*>.*cron" "$REPO_ROOT" --include="*.sh" 2>/dev/null | grep -Ev "^[[:space:]]*#" | grep -Evi "Example|example" | wc -l)
    local total_cron=$((cron_mods + cron_writes))
    if [ "$total_cron" -eq 0 ]; then
        check_pass "No unauthorized cron job modifications"
    else
        check_warn "Found $total_cron cron modifications (review needed)"
    fi
    
    # Check for hidden processes or background connections (excluding documentation)
    local background_nc=$(grep -rE "nc -l|netcat -l|ncat -l" "$REPO_ROOT" --include="*.sh" 2>/dev/null | grep -v "^\s*#" | grep -Evi "example|Example|test" | wc -l)
    if [ "$background_nc" -eq 0 ]; then
        check_pass "No unauthorized listening ports (nc/netcat)"
    else
        check_fail "Found netcat listeners (potential backdoor)"
    fi
    
    # Check for suspicious systemd service creation to unknown binaries
    # Use --exclude to properly exclude files (not grep output)
    local systemd_services=$(grep -r "ExecStart=/tmp/" "$REPO_ROOT" --include="*.sh" --exclude="security-check.sh" 2>/dev/null | grep -Ev "waydroid-setup\.sh|waydroid-env\.sh" || echo "")
    local suspicious_exec=0
    if [ -n "$systemd_services" ]; then
        suspicious_exec=$(echo "$systemd_services" | wc -l)
    fi
    
    if [ "$suspicious_exec" -eq 0 ]; then
        check_pass "No suspicious systemd service executables"
    else
        check_fail "Found systemd services executing from /tmp"
    fi
}

# Check 7: Validate all external URLs are legitimate
check_repository_sources() {
    print_section "Validating Software Repository Sources"
    
    # Check if all apt repositories are from official sources
    local unofficial_repos=$(grep -r "add-apt-repository\|sources.list" "$REPO_ROOT" --include="*.sh" 2>/dev/null | grep -v "repo.waydro.id\|debian.org\|ubuntu.com" | grep -v "^#" | wc -l)
    
    # Check for GPG key verification
    local gpg_verify=$(grep -r "gpg --dearmor\|apt-key add" "$REPO_ROOT" --include="*.sh" 2>/dev/null | wc -l)
    if [ "$gpg_verify" -gt 0 ]; then
        check_pass "Repository keys are GPG-verified"
    else
        check_warn "Repository key verification not found"
    fi
}

# Check 8: Input validation
check_input_validation() {
    print_section "Checking Input Validation"
    
    # Look for parameter validation patterns (use -E for regex operator =~)
    local validation_patterns=$(grep -rE '^[[:space:]]*if.*\[\[.*=~' "$REPO_ROOT" --include="*.sh" 2>/dev/null | wc -l)
    if [ "$validation_patterns" -gt 3 ]; then
        check_pass "Input validation patterns found ($validation_patterns instances)"
    else
        check_warn "Limited input validation detected"
    fi
}

# Main execution
main() {
    print_header
    
    echo "Analyzing scripts in: $REPO_ROOT"
    echo "Total bash scripts: $(find "$REPO_ROOT" -type f -name "*.sh" 2>/dev/null | wc -l)"
    echo ""
    
    # Run all checks
    check_data_exfiltration
    check_dangerous_commands
    check_credential_theft
    check_obfuscation
    check_credential_security
    check_backdoors
    check_repository_sources
    check_input_validation
    
    # Print summary
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Security Check Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Total Checks:    $TOTAL_CHECKS"
    echo -e "${GREEN}Passed:          $PASSED_CHECKS${NC}"
    echo -e "${YELLOW}Warnings:        $WARNINGS${NC}"
    echo -e "${RED}Failed:          $FAILED_CHECKS${NC}"
    echo ""
    
    # Print issues if any
    if [ $FAILED_CHECKS -gt 0 ]; then
        echo -e "${RED}⚠ SECURITY ISSUES DETECTED:${NC}"
        for issue in "${ISSUES[@]}"; do
            echo -e "  ${RED}•${NC} $issue"
        done
        echo ""
    fi
    
    # Print suspicious patterns if any
    if [ ${#SUSPICIOUS_PATTERNS[@]} -gt 0 ]; then
        echo -e "${YELLOW}Suspicious Patterns Found (Review Recommended):${NC}"
        for pattern in "${SUSPICIOUS_PATTERNS[@]}"; do
            echo -e "  ${YELLOW}•${NC} $pattern"
        done
        echo ""
    fi
    
    # Overall verdict
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    if [ $FAILED_CHECKS -eq 0 ]; then
        echo -e "${GREEN}✓ OVERALL VERDICT: SAFE TO USE${NC}"
        echo ""
        echo "No critical security issues detected."
        echo "The scripts appear to be legitimate and safe to run."
        echo ""
        echo "Review the detailed security analysis in SECURITY-ANALYSIS.md"
        exit 0
    elif [ $FAILED_CHECKS -le 2 ] && [ $WARNINGS -le 5 ]; then
        echo -e "${YELLOW}⚠ OVERALL VERDICT: REVIEW RECOMMENDED${NC}"
        echo ""
        echo "Some potential security concerns detected."
        echo "Please review the issues above before proceeding."
        echo ""
        exit 1
    else
        echo -e "${RED}✗ OVERALL VERDICT: SECURITY CONCERNS${NC}"
        echo ""
        echo "Multiple security issues detected."
        echo "DO NOT RUN these scripts until issues are resolved."
        echo ""
        exit 2
    fi
}

# Run the security check
main "$@"
