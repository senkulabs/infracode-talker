#!/bin/bash

# Go deployer Setup Script
# This script automates the server setup for deploying Go project on Ubuntu

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_CHROMIUM=false
INSTALL_REDIS=false
INSTALL_REDIS_CLI=false
REDIS_PASS=""
HOSTNAME=""
CHROMIUM_PATH=""

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

show_help() {
    cat << EOF
Go deployer Setup Script

USAGE:
    $0 --hostname=NAME [OPTIONS]

REQUIRED ARGUMENTS:
    --hostname=NAME         Deploy directory name (e.g. sandbox.gladion-worker)

OPTIONS:
    --with-chromium         Install Chromium (required for lighthouse worker)
    --with-redis            Install Redis server (includes redis-cli)
    --with-redis-cli        Install redis-cli only (use when Redis runs elsewhere)
    --redis-pass=PASSWORD   Redis password (auto-generated if --with-redis but omitted)
    --help                  Show this help message

EXAMPLES:
    $0 --hostname=sandbox.gladion-worker
    $0 --hostname=sandbox.gladion-worker --with-chromium
    $0 --hostname=sandbox.gladion-worker --with-chromium --with-redis
    $0 --hostname=sandbox.gladion-worker --with-redis-cli

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --hostname=*) HOSTNAME="${1#*=}"; shift ;;
            --with-chromium) INSTALL_CHROMIUM=true; shift ;;
            --with-redis) INSTALL_REDIS=true; shift ;;
            --with-redis-cli) INSTALL_REDIS_CLI=true; shift ;;
            --redis-pass=*) REDIS_PASS="${1#*=}"; shift ;;
            --help) show_help; exit 0 ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done
}

validate_arguments() {
    if [[ -z "$HOSTNAME" ]]; then
        log_error "Missing required argument: --hostname"
        echo ""
        show_help
        exit 1
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

configure_ufw() {
    log_step "Configuring UFW firewall..."
    ufw allow OpenSSH
    ufw --force enable
    log_info "UFW enabled with OpenSSH allowed"
}

install_chromium() {
    if [[ "$INSTALL_CHROMIUM" == false ]]; then
        log_info "Skipping Chromium installation (use --with-chromium to install)"
        return
    fi

    log_step "Installing Chromium..."
    apt update -y
    apt install -y chromium-browser 2>/dev/null || apt install -y chromium

    CHROMIUM_PATH=$(command -v chromium-browser 2>/dev/null || command -v chromium 2>/dev/null || echo "")

    if [[ -z "$CHROMIUM_PATH" ]]; then
        log_error "Chromium installation failed"
        exit 1
    fi

    log_info "Chromium installed at: ${CHROMIUM_PATH}"
}

install_acl() {
    log_step "Installing ACL..."
    apt install -y acl
    log_info "ACL installed"
}

install_redis_cli() {
    if [[ "$INSTALL_REDIS_CLI" == false ]]; then
        log_info "Skipping redis-cli installation (use --with-redis-cli to install)"
        return
    fi

    if [[ "$INSTALL_REDIS" == true ]]; then
        log_info "redis-cli already covered by redis-server install — skipping standalone"
        return
    fi

    log_step "Installing redis-tools (redis-cli only)..."
    apt install -y redis-tools

    if command -v redis-cli >/dev/null 2>&1; then
        log_info "redis-cli installed: $(redis-cli --version)"
    else
        log_error "redis-cli installation failed"
        exit 1
    fi
}

install_redis() {
    if [[ "$INSTALL_REDIS" == false ]]; then
        log_info "Skipping Redis installation (use --with-redis to install)"
        return
    fi

    log_step "Installing Redis..."
    apt install -y redis-server

    if [[ -z "$REDIS_PASS" ]]; then
        REDIS_PASS="$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)"
        log_info "Generated Redis password"
    fi

    local redis_conf="/etc/redis/redis.conf"
    if grep -qE '^[[:space:]]*requirepass[[:space:]]+' "$redis_conf"; then
        sed -i "s|^[[:space:]]*requirepass[[:space:]]\+.*|requirepass ${REDIS_PASS}|" "$redis_conf"
    elif grep -qE '^[[:space:]]*#[[:space:]]*requirepass[[:space:]]+' "$redis_conf"; then
        sed -i "s|^[[:space:]]*#[[:space:]]*requirepass[[:space:]]\+.*|requirepass ${REDIS_PASS}|" "$redis_conf"
    else
        echo "requirepass ${REDIS_PASS}" >> "$redis_conf"
    fi

    systemctl enable redis-server
    systemctl restart redis-server

    if systemctl is-active --quiet redis-server; then
        log_info "Redis installed and running"
    else
        log_error "Redis failed to start"
        systemctl status redis-server
        exit 1
    fi
}

create_deployer_user() {
    if id "deployer" &>/dev/null; then
        log_warn "User 'deployer' already exists — skipping creation"
    else
        log_step "Creating deployer user..."
        adduser --disabled-password --gecos "" deployer
        log_info "Deployer user created"
    fi
}


configure_deployer_sudo() {
    log_step "Configuring passwordless sudo for deployer..."

    local sudoers_file="/etc/sudoers.d/deployer-worker"
    local tmp_file
    tmp_file="$(mktemp)"

    cat > "$tmp_file" << 'EOF'
deployer ALL=(ALL) NOPASSWD: /usr/bin/supervisorctl
EOF

    if visudo -cf "$tmp_file" >/dev/null 2>&1; then
        install -m 0440 -o root -g root "$tmp_file" "$sudoers_file"
        rm -f "$tmp_file"
        log_info "Sudoers entry installed at ${sudoers_file}"
    else
        rm -f "$tmp_file"
        log_error "Sudoers syntax invalid; aborting"
        exit 1
    fi
}

create_ssh_key_pair() {
    if [[ -f /home/deployer/.ssh/id_ed25519 ]]; then
        log_warn "SSH key already exists — skipping"
        return
    fi

    log_step "Creating SSH key pair for deployer..."
    sudo -u deployer mkdir -p /home/deployer/.ssh
    sudo -u deployer ssh-keygen -t ed25519 -C "Deploy gladion-worker via CI/CD" -N "" -f /home/deployer/.ssh/id_ed25519
    sudo -u deployer sh -c 'cd /home/deployer/.ssh && cat id_ed25519.pub >> authorized_keys'
    sudo -u deployer chmod 600 /home/deployer/.ssh/authorized_keys
    sudo -u deployer chmod 700 /home/deployer/.ssh
    log_info "SSH key pair created"
}

create_deploy_dir() {
    local deploy_path="/opt/${HOSTNAME}"
    log_step "Creating deploy directory at ${deploy_path}..."
    mkdir -p "${deploy_path}"
    setfacl -R -m u:deployer:rwx -m d:u:deployer:rwx "${deploy_path}"
    log_info "Deploy directory created"
}

enable_network_online_target() {
    log_step "Ensuring network-online.target is satisfied at boot..."

    if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-networkd-wait-online.service'; then
        systemctl enable systemd-networkd-wait-online.service >/dev/null 2>&1 || true
        log_info "Enabled systemd-networkd-wait-online.service"
    elif systemctl list-unit-files 2>/dev/null | grep -q '^NetworkManager-wait-online.service'; then
        systemctl enable NetworkManager-wait-online.service >/dev/null 2>&1 || true
        log_info "Enabled NetworkManager-wait-online.service"
    else
        log_warn "No wait-online service found; network-online.target may not block boot"
    fi
}

install_systemd_services() {
    local deploy_path="/opt/${HOSTNAME}"
    local service_file="/etc/systemd/system/${HOSTNAME}.service"
    log_step "Installing systemd service file at ${service_file}..."

    local after_units="network-online.target"
    local wants_units="network-online.target"
    if [[ "$INSTALL_REDIS" == true ]]; then
        after_units="${after_units} redis-server.service"
        wants_units="${wants_units} redis-server.service"
    fi

    cat > "${service_file}" << EOF
[Unit]
Description=${HOSTNAME} Worker
After=${after_units}
Wants=${wants_units}

[Service]
Type=simple
User=deployer
Group=deployer
WorkingDirectory=${deploy_path}/current
ExecStart=${deploy_path}/current/bin/gladion-probe
EnvironmentFile=${deploy_path}/shared/.env
Restart=on-failure
RestartSec=5s
TimeoutStopSec=60s
KillMode=mixed
KillSignal=SIGTERM
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${HOSTNAME}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${HOSTNAME}"
    log_info "Service installed and enabled: ${HOSTNAME}.service (start after first deploy)"
}

show_summary() {
    local deploy_path="/opt/${HOSTNAME}"
    echo ""
    echo -e "${GREEN}================================="
    echo -e "    INSTALLATION SUMMARY"
    echo -e "=================================${NC}"
    echo ""
    if [[ "$INSTALL_CHROMIUM" == true ]]; then
        echo -e "✅ Chromium installed: ${CHROMIUM_PATH}"
    else
        echo -e "⏭️  Chromium skipped (use --with-chromium to install)"
    fi
    echo -e "✅ ACL installed"
    if [[ "$INSTALL_REDIS" == true ]]; then
        echo -e "✅ Redis installed and running"
    elif [[ "$INSTALL_REDIS_CLI" == true ]]; then
        echo -e "✅ redis-cli installed (no server)"
    else
        echo -e "⏭️  Redis skipped (use --with-redis or --with-redis-cli)"
    fi
    echo -e "✅ Deployer user ready"
    echo -e "✅ Sudoers configured: /etc/sudoers.d/deployer-worker"
    echo -e "✅ Deploy directory: ${deploy_path}"
    echo -e "✅ Service installed and enabled: ${HOSTNAME}.service"
    echo ""
    echo -e "${YELLOW}Important Notes:${NC}"
    echo -e "• Service is enabled but NOT started — start after first deploy:"
    echo -e "  systemctl start ${HOSTNAME}"
    echo -e "• View logs:"
    echo -e "  journalctl -u ${HOSTNAME} -f"
    if [[ "$INSTALL_REDIS" == true ]]; then
        echo -e "• Redis password: ${REDIS_PASS}"
    fi
    if [[ "$INSTALL_CHROMIUM" == true ]]; then
        echo -e "• Set CHROME_PATH=${CHROMIUM_PATH} in your .env"
    fi
    echo ""
    echo -e "${GREEN}Setup completed successfully!${NC}"
}

display_ssh_info() {
    log_step "Display SSH Key Information..."

    echo ""
    echo -e "${BLUE}================================="
    echo -e "    SSH KEY INFORMATION"
    echo -e "=================================${NC}"
    echo ""

    if [[ -f /home/deployer/.ssh/id_ed25519 ]]; then
        echo -e "${YELLOW}SSH Private Key:${NC}"
        echo -e "${GREEN}Copy this private key to your CI/CD system:${NC}"
        echo ""
        cat /home/deployer/.ssh/id_ed25519
        echo ""
    else
        log_warn "SSH private key already existed — retrieve it separately"
    fi

    echo -e "${YELLOW}Host Key Information:${NC}"
    echo -e "${GREEN}Add these to your known_hosts file or CI/CD system:${NC}"
    echo ""

    local hostname_val
    hostname_val=$(hostname -f 2>/dev/null || hostname)
    local ip_address
    ip_address=$(hostname -I | awk '{print $1}')

    for host in "localhost" "$hostname_val" "$ip_address"; do
        echo "# Host keys for: $host"
        if command -v ssh-keyscan >/dev/null 2>&1; then
            ssh-keyscan -t ed25519 "$host" 2>/dev/null | head -10
        else
            log_warn "ssh-keyscan not found"
        fi
        echo ""
    done

    echo -e "${BLUE}=================================${NC}"
    echo ""
}

main() {
    log_info "Starting Gladion Worker setup..."

    parse_arguments "$@"
    validate_arguments

    echo ""
    echo -e "${BLUE}Configuration:${NC}"
    echo -e "• Hostname: ${HOSTNAME}"
    echo -e "• Deploy path: /opt/${HOSTNAME}"
    echo -e "• Install Chromium: ${INSTALL_CHROMIUM}"
    echo -e "• Install Redis (server): ${INSTALL_REDIS}"
    echo -e "• Install redis-cli only: ${INSTALL_REDIS_CLI}"
    echo ""

    read -p "Do you want to proceed with this configuration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled."
        exit 0
    fi

    check_root

    configure_ufw
    install_chromium
    install_acl
    install_redis_cli
    install_redis
    create_deployer_user
    configure_deployer_sudo
    create_ssh_key_pair
    create_deploy_dir
    enable_network_online_target
    install_systemd_services

    show_summary
    display_ssh_info
}

main "$@"
