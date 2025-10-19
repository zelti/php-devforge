#!/bin/bash

# Script para agregar DNS local (127.0.0.1) a la configuración existente
# Compatible con macOS, Ubuntu, Debian y otros sistemas Linux

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
DNS_SERVER="127.0.0.1"
BACKUP_DIR="$HOME/.dns-backup-$(date +%Y%m%d-%H%M%S)"

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}   Local DNS Setup Script${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        print_status "Detected: macOS"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        print_status "Detected: Debian/Ubuntu"
    elif [[ -f /etc/redhat-release ]]; then
        OS="rhel"
        print_status "Detected: RHEL/CentOS/Fedora"
    elif [[ -f /etc/arch-release ]]; then
        OS="arch"
        print_status "Detected: Arch Linux"
    else
        OS="unknown"
        print_warning "Unknown OS, trying generic Linux approach"
    fi
}

create_backup() {
    mkdir -p "$BACKUP_DIR"
    print_status "Creating backup directory: $BACKUP_DIR"
}

backup_dns_macos() {
    # Backup current DNS servers for all network services
    networksetup -listallnetworkservices | tail -n +2 | while read service; do
        if [[ "$service" != *"*"* ]]; then  # Skip disabled services
            current_dns=$(networksetup -getdnsservers "$service" 2>/dev/null)
            if [[ "$current_dns" != "There aren't any DNS Servers set"* ]]; then
                echo "$current_dns" > "$BACKUP_DIR/dns-${service// /_}.backup"
                print_status "Backed up DNS for: $service"
            fi
        fi
    done
}

backup_dns_linux() {
    # Backup resolv.conf
    if [[ -f /etc/resolv.conf ]]; then
        sudo cp /etc/resolv.conf "$BACKUP_DIR/resolv.conf.backup"
        print_status "Backed up /etc/resolv.conf"
    fi
    
    # Backup NetworkManager configurations
    if command -v nmcli &> /dev/null; then
        nmcli connection show --active | tail -n +2 | while read line; do
            name=$(echo "$line" | awk '{print $1}')
            uuid=$(echo "$line" | awk '{print $2}')
            nmcli connection show "$uuid" > "$BACKUP_DIR/nm-${name}.backup" 2>/dev/null || true
        done
        print_status "Backed up NetworkManager connections"
    fi
}

setup_dns_macos() {
    print_status "Configuring DNS for macOS..."
    
    # Get all active network services
    networksetup -listallnetworkservices | tail -n +2 | while read service; do
        if [[ "$service" != *"*"* ]]; then  # Skip disabled services
            print_status "Configuring DNS for: $service"
            
            # Get current DNS servers
            current_dns=$(networksetup -getdnsservers "$service" 2>/dev/null)
            
            if [[ "$current_dns" == "There aren't any DNS Servers set"* ]]; then
                # No DNS servers set, just add ours
                sudo networksetup -setdnsservers "$service" $DNS_SERVER
            else
                # Add our DNS server to the beginning of the list
                dns_list="$DNS_SERVER $current_dns"
                sudo networksetup -setdnsservers "$service" $dns_list
            fi
            
            print_status "✓ DNS configured for: $service"
        fi
    done
    
    # Flush DNS cache
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder 2>/dev/null || true
    print_status "✓ DNS cache flushed"
}

setup_dns_networkmanager() {
    if ! command -v nmcli &> /dev/null; then
        print_warning "NetworkManager not found, skipping..."
        return
    fi
    
    print_status "Configuring DNS via NetworkManager..."
    
    # Get active connections
    nmcli -t -f NAME connection show --active | while IFS= read -r connection; do
        if [[ -n "$connection" ]]; then
            print_status "Configuring connection: $connection"
            
            # Get current DNS settings
            current_dns=$(nmcli connection show "$connection" | grep "ipv4.dns:" | awk '{print $2}' | tr ',' ' ')
            
            if [[ -n "$current_dns" && "$current_dns" != "--" ]]; then
                # Add our DNS to the beginning
                new_dns="$DNS_SERVER,$current_dns"
            else
                # No current DNS, just use ours plus common fallbacks
                new_dns="$DNS_SERVER,8.8.8.8,1.1.1.1"
            fi
            
            # Apply DNS settings
            nmcli connection modify "$connection" ipv4.dns "$new_dns"
            nmcli connection modify "$connection" ipv4.ignore-auto-dns no
            
            # Restart connection to apply changes
            nmcli connection down "$connection" >/dev/null 2>&1 || true
            nmcli connection up "$connection" >/dev/null 2>&1 || true
            
            print_status "✓ DNS configured for: $connection"
        fi
    done
}

setup_dns_systemd_resolved() {
    if ! systemctl is-active --quiet systemd-resolved; then
        print_warning "systemd-resolved not active, skipping..."
        return
    fi
    
    print_status "Configuring DNS via systemd-resolved..."
    
    # Create resolved.conf.d directory if it doesn't exist
    sudo mkdir -p /etc/systemd/resolved.conf.d
    
    # Create custom DNS configuration
    cat << EOF | sudo tee /etc/systemd/resolved.conf.d/local-dns.conf >/dev/null
[Resolve]
DNS=${DNS_SERVER}
Domains=~.
EOF
    
    # Restart systemd-resolved
    sudo systemctl restart systemd-resolved
    print_status "✓ systemd-resolved configured"
}

setup_dns_debian() {
    print_status "Configuring DNS for Debian/Ubuntu..."
    
    # Try NetworkManager first
    if command -v nmcli &> /dev/null && systemctl is-active --quiet NetworkManager; then
        setup_dns_networkmanager
    # Try systemd-resolved
    elif systemctl is-active --quiet systemd-resolved; then
        setup_dns_systemd_resolved
    else
        # Fallback to direct resolv.conf modification
        print_status "Using direct resolv.conf modification..."
        
        # Get current nameservers
        current_nameservers=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ')
        
        # Create new resolv.conf
        {
            echo "# Generated by local DNS setup script"
            echo "nameserver $DNS_SERVER"
            if [[ -n "$current_nameservers" ]]; then
                for ns in $current_nameservers; do
                    if [[ "$ns" != "$DNS_SERVER" ]]; then
                        echo "nameserver $ns"
                    fi
                done
            else
                echo "nameserver 8.8.8.8"
                echo "nameserver 1.1.1.1"
            fi
            
            # Preserve other settings
            grep -v "^nameserver" /etc/resolv.conf 2>/dev/null || true
        } | sudo tee /etc/resolv.conf.new >/dev/null
        
        sudo mv /etc/resolv.conf.new /etc/resolv.conf
        print_status "✓ resolv.conf updated"
    fi
}

test_dns() {
    print_status "Testing DNS resolution..."
    
    # Test external DNS
    if nslookup google.com >/dev/null 2>&1; then
        print_status "✓ External DNS working"
    else
        print_error "✗ External DNS not working"
        return 1
    fi
    
    # Test local DNS if domain is provided
    if [[ -n "$1" ]]; then
        if nslookup "test.$1" >/dev/null 2>&1; then
            print_status "✓ Local DNS working for $1"
        else
            print_warning "Local DNS test for $1 failed (normal if dnsmasq not running)"
        fi
    fi
}

show_current_dns() {
    print_status "Current DNS configuration:"
    
    case $OS in
        macos)
            networksetup -listallnetworkservices | tail -n +2 | while read service; do
                if [[ "$service" != *"*"* ]]; then
                    echo "  $service:"
                    networksetup -getdnsservers "$service" | sed 's/^/    /'
                fi
            done
            ;;
        *)
            if [[ -f /etc/resolv.conf ]]; then
                echo "  /etc/resolv.conf:"
                grep "nameserver" /etc/resolv.conf | sed 's/^/    /'
            fi
            ;;
    esac
}

restore_dns() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_error "No backup directory found. Please specify backup directory with -r /path/to/backup"
        exit 1
    fi
    
    print_status "Restoring DNS configuration from: $BACKUP_DIR"
    
    case $OS in
        macos)
            for backup_file in "$BACKUP_DIR"/dns-*.backup; do
                if [[ -f "$backup_file" ]]; then
                    service_name=$(basename "$backup_file" .backup | sed 's/dns-//' | tr '_' ' ')
                    dns_servers=$(cat "$backup_file")
                    sudo networksetup -setdnsservers "$service_name" $dns_servers
                    print_status "✓ Restored DNS for: $service_name"
                fi
            done
            sudo dscacheutil -flushcache
            sudo killall -HUP mDNSResponder 2>/dev/null || true
            ;;
        *)
            if [[ -f "$BACKUP_DIR/resolv.conf.backup" ]]; then
                sudo cp "$BACKUP_DIR/resolv.conf.backup" /etc/resolv.conf
                print_status "✓ Restored /etc/resolv.conf"
            fi
            
            # Remove systemd-resolved custom config
            sudo rm -f /etc/systemd/resolved.conf.d/local-dns.conf
            sudo systemctl restart systemd-resolved 2>/dev/null || true
            ;;
    esac
    
    print_status "✓ DNS configuration restored"
}

show_help() {
    cat << EOF
Local DNS Setup Script

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -t, --test [domain] Test DNS resolution (optionally for specific domain)
    -s, --show          Show current DNS configuration
    -r, --restore [dir] Restore DNS from backup directory
    -d, --domain domain Set domain for testing (default: none)

Examples:
    $0                           # Setup local DNS
    $0 --test phpbox.dev        # Test DNS for domain
    $0 --show                   # Show current DNS config
    $0 --restore ~/.dns-backup-* # Restore from backup

EOF
}

main() {
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -t|--test)
            detect_os
            test_dns "$2"
            exit 0
            ;;
        -s|--show)
            detect_os
            show_current_dns
            exit 0
            ;;
        -r|--restore)
            detect_os
            BACKUP_DIR="${2:-$BACKUP_DIR}"
            restore_dns
            exit 0
            ;;
        *)
            print_header
            detect_os
            create_backup
            
            case $OS in
                macos)
                    backup_dns_macos
                    setup_dns_macos
                    ;;
                debian)
                    backup_dns_linux
                    setup_dns_debian
                    ;;
                *)
                    backup_dns_linux
                    setup_dns_debian
                    ;;
            esac
            
            echo ""
            print_status "✓ DNS configuration completed!"
            print_status "Backup saved to: $BACKUP_DIR"
            echo ""
            print_warning "To restore original settings:"
            print_warning "$0 --restore $BACKUP_DIR"
            echo ""
            test_dns "$2"
            ;;
    esac
}

main "$@"