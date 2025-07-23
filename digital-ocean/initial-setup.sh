#!/bin/bash

# Laravel with Nginx Unit Setup Script
# This script automates the installation of Laravel with Nginx Unit on Ubuntu

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Step 1: Install PHP and extensions for Laravel
install_php() {
    log_info "Installing PHP and Laravel extensions..."
    apt update
    apt install php-intl php-bcmath php-cli php-curl php-gd php-mbstring php-mysql php-pgsql php-redis php-sqlite3 php-xml php-zip unzip -y
    log_info "PHP and extensions installed successfully"
}

# Step 2: Install Nginx Unit
install_nginx_unit() {
    log_info "Installing Nginx Unit..."
    
    # Download & save Nginx signing key
    curl --output /usr/share/keyrings/nginx-keyring.gpg https://unit.nginx.org/keys/nginx-keyring.gpg
    
    # Configure unit's repository
    cat > /etc/apt/sources.list.d/unit.list << EOF
deb [signed-by=/usr/share/keyrings/nginx-keyring.gpg] https://packages.nginx.org/unit/ubuntu/ noble unit
deb-src [signed-by=/usr/share/keyrings/nginx-keyring.gpg] https://packages.nginx.org/unit/ubuntu/ noble unit
EOF
    
    # Install unit
    apt update && apt install unit -y
    apt install unit-dev unit-php -y
    
    # Start and enable unit service
    systemctl restart unit
    systemctl enable unit
    
    # Check status
    if systemctl is-active --quiet unit; then
        log_info "Nginx Unit installed and running successfully"
    else
        log_error "Nginx Unit failed to start"
        systemctl status unit
        exit 1
    fi
}

# Step 3: Install Composer
install_composer() {
    log_info "Installing Composer..."
    curl -sLS https://getcomposer.org/installer | php -- --install-dir=/usr/bin/ --filename=composer
    log_info "Composer installed successfully"
}

# Step 4: Create web directory
create_web_directory() {
    log_info "Creating /var/www directory..."
    mkdir -p /var/www
    log_info "Web directory created"
}

# Step 5: Install PostgreSQL
install_postgresql() {
    log_info "Installing PostgreSQL..."
    apt install postgresql postgresql-contrib -y
    
    # Start and enable PostgreSQL
    systemctl start postgresql
    systemctl enable postgresql
    
    # Check if PostgreSQL is running
    if systemctl is-active --quiet postgresql; then
        log_info "PostgreSQL installed and running successfully"
        log_info "Default postgres user created. You can set password with: sudo -u postgres psql -c \"ALTER USER postgres PASSWORD 'your_password';\""
    else
        log_error "PostgreSQL failed to start"
        systemctl status postgresql
        exit 1
    fi
}

# Step 6: Install Redis
install_redis() {
    log_info "Installing Redis..."
    apt install redis-server -y
    
    # Start and enable Redis
    systemctl start redis-server
    systemctl enable redis-server
    
    # Check if Redis is running
    if systemctl is-active --quiet redis-server; then
        log_info "Redis installed and running successfully"
        # Test Redis connection
        redis-cli ping > /dev/null && log_info "Redis is responding to ping"
    else
        log_error "Redis failed to start"
        systemctl status redis-server
        exit 1
    fi
}


# Step 7: Install Certbot
install_certbot() {
    log_info "Installing Certbot..."
    
    # Install system dependencies
    apt update && apt install python3 python3-venv libaugeas-dev -y
    
    # Setup python virtual environment
    python3 -m venv /opt/certbot/
    /opt/certbot/bin/pip install --upgrade pip
    
    # Install certbot
    /opt/certbot/bin/pip install certbot
    
    # Prepare certbot command by symlink
    ln -sf /opt/certbot/bin/certbot /usr/bin/certbot
    
    log_info "Certbot installed successfully"
}

# Step 8: Install ACL
install_acl() {
    log_info "Installing ACL (Access Control List)..."

    apt install -y acl

    log_info "ACL installed successfully"
}

# Step 9: Create deployer user + give access to deployer user
create_deployer_user() {
    log_info "Create deployer user..."

    adduser --disabled-password --gecos "" deployer

    log_info "Give deployer user access to /var/www directory..."
    setfacl -R -m u:deployer:rwx /var/www

    log_info "Add deployer user to unit (nginx unit) group..."
    usermod -a -G unit deployer
}

# Step 10: Create SSH Key Pair
create_ssh_key_pair() {
    log_info "Creating SSH Key Pair for deployer user..."
    
    # Run commands as deployer user without interactive shell
    sudo -u deployer mkdir -p /home/deployer/.ssh
    sudo -u deployer ssh-keygen -t ed25519 -C "Deploy web app with CI/CD" -N "" -f /home/deployer/.ssh/id_ed25519
    sudo -u deployer sh -c 'cd /home/deployer/.ssh && cat id_ed25519.pub >> authorized_keys'
    sudo -u deployer chmod 600 /home/deployer/.ssh/authorized_keys
    sudo -u deployer chmod 700 /home/deployer/.ssh
}

# Main execution
main() {
    log_info "Starting Laravel with Nginx Unit setup..."
    
    check_root
    
    # Basic installation steps
    install_php
    install_nginx_unit
    install_composer
    create_web_directory
    install_postgresql
    install_redis
    install_certbot
    install_acl
    create_deployer_user
    create_ssh_key_pair
}

# Run main function
main "$@"