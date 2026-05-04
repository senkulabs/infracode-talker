#!/bin/bash

# Laravel with Nginx PHP-FPM Setup Script
# This script automates the installation of Laravel with Nginx PHP-FPM on Ubuntu

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
INSTALL_REDIS=false
DB_ENGINE="postgresql"
DB_NAME=""
DB_USER=""
DB_PASS=""

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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

show_help() {
    cat << EOF
Enhanced Laravel with Nginx PHP-FPM Setup Script

USAGE:
    $0 --db-name=NAME -db-user=USER --db-pass=PASS [OPTIONS]

REQUIRED ARGUMENTS:
    --db-name=NAME          Database name
    --db-user=USER          Database user
    --db-pass=PASSWORD      Database password

OPTIONS:
    --db-engine=ENGINE      Database engine: postgresql (default) or mariadb
    --with-redis            Install Redis server
    --help                  Show this help message

EXAMPLES:
    $0 --db-name=myapp --db-user=myuser --db-pass=mypass
    $0 --db-name=myapp --db-user=myuser --db-pass=mypass --db-engine=mariadb
    $0 --db-name=myapp --db-user=myuser --db-pass=mypass --with-redis

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --with-redis)
                INSTALL_REDIS=true
                shift
                ;;
            --db-engine=*)
                DB_ENGINE="${1#*=}"
                shift
                ;;
            --db-name=*)
                DB_NAME="${1#*=}"
                shift
                ;;
            --db-user=*)
                DB_USER="${1#*=}"
                shift
                ;;
            --db-pass=*)
                DB_PASS="${1#*=}"
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

validate_arguments() {
    local missing_args=()

    if [[ -z "$DB_NAME" ]]; then
        missing_args+=("--db-name")
    fi

    if [[ -z "$DB_USER" ]]; then
        missing_args+=("--db-user")
    fi

    if [[ -z "$DB_PASS" ]]; then
        missing_args+=("--db-pass")
    fi

    if [[ ${#missing_args[@]} -gt 0 ]]; then
        log_error "Missing required arguments: ${missing_args[*]}"
        echo ""
        show_help
        exit 1
    fi

    if [[ "$DB_ENGINE" != "postgresql" && "$DB_ENGINE" != "mariadb" ]]; then
        log_error "Invalid --db-engine value: '$DB_ENGINE'. Must be 'postgresql' or 'mariadb'."
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

# Step 0: Configure UFW
configure_ufw() {
    log_step "Configuring UFW firewall..."
    ufw allow OpenSSH
    ufw --force enable
    log_info "UFW enabled with OpenSSH allowed"
}

# Step 1: Install PHP and extensions for Laravel
install_php() {
    log_info "Installing PHP and Laravel extensions..."
    apt update
    apt install php-intl php-bcmath php-cli php-curl php-fpm php-gd php-mbstring php-mysql php-pgsql php-redis php-sqlite3 php-xml php-zip unzip -y
    log_info "PHP and extensions installed successfully"
}

# Step 2: Install Nginx
install_nginx() {
    log_info "Installing Nginx..."

    apt update
    # Install may fail post-install if IPv6 is disabled on the host
    # (default site listens on [::]:80). Tolerate failure, patch, retry.
    apt install -y nginx || log_warn "Nginx post-install failed; attempting IPv6 patch"

    if ! ip -6 addr show scope global 2>/dev/null | grep -q inet6; then
        log_warn "IPv6 not available on host; disabling IPv6 listen in default site"
        if [[ -f /etc/nginx/sites-available/default ]]; then
            sed -i 's|^\(\s*\)listen \[::\]:80|\1# listen [::]:80|' /etc/nginx/sites-available/default
        fi
    fi

    # Finish any pending dpkg configuration (nginx post-install retry)
    dpkg --configure -a

    systemctl enable nginx
    systemctl restart nginx

    if systemctl is-active --quiet nginx; then
        log_info "Nginx installed and running successfully"
    else
        log_error "Nginx failed to start"
        systemctl status nginx
        exit 1
    fi

    ufw allow 'Nginx HTTP'
    log_info "UFW: Nginx HTTP allowed"
}

# Step 3: Install Composer
install_composer() {
    log_info "Installing Composer..."
    curl -sLS https://getcomposer.org/installer | php -- --install-dir=/usr/bin/ --filename=composer
    log_info "Composer installed successfully"
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

# Step 6: Configure PostgreSQL Database
configure_postgresql_database() {
    log_step "Configuring PostgreSQL database..."

    # Create database and user using the integrated PostgreSQL setup
    sudo -u postgres psql << EOF
-- Create your Laravel application database
CREATE DATABASE ${DB_NAME};

-- Create a dedicated user for your Laravel app
CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';

-- Connect to the application database
\\c ${DB_NAME}

-- Grant the necessary privileges to DB_USER
GRANT ALL PRIVILEGES ON SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${DB_USER};

-- Exit
\\q
EOF

    log_info "PostgreSQL database configured successfully"
    log_info "Database: ${DB_NAME}"
    log_info "User: ${DB_USER}"
    log_info "Password: ${DB_PASS}"
}

# Step 5 (alt): Install MariaDB
install_mariadb() {
    log_info "Installing MariaDB..."
    apt install mariadb-server -y

    # Start and enable MariaDB
    systemctl start mariadb
    systemctl enable mariadb

    # Check if MariaDB is running
    if systemctl is-active --quiet mariadb; then
        log_info "MariaDB installed and running successfully"
    else
        log_error "MariaDB failed to start"
        systemctl status mariadb
        exit 1
    fi
}

# Step 6 (alt): Configure MariaDB Database
configure_mariadb_database() {
    log_step "Configuring MariaDB database..."

    # Root uses unix_socket auth by default on Ubuntu MariaDB
    mariadb <<EOF
-- Create your Laravel application database
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create a dedicated user for your Laravel app
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';

-- Grant privileges on the application database
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';

-- Apply privilege changes
FLUSH PRIVILEGES;
EOF

    log_info "MariaDB database configured successfully"
    log_info "Database: ${DB_NAME}"
    log_info "User: ${DB_USER}"
    log_info "Password: ${DB_PASS}"
}

# Step 7: Install Redis (optional)
install_redis() {
    if [[ "$INSTALL_REDIS" == true ]]; then
        log_step "Installing Redis..."
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
    else
        log_info "Skipping Redis installation (use --with-redis to install)"
    fi
}


# Step 8: Install Certbot
install_certbot() {
    log_step "Installing Certbot..."

    apt install -y certbot python3-certbot-nginx

    log_info "Certbot installed successfully"
}

# Step 9: Install ACL
install_acl() {
    log_step "Installing ACL (Access Control List)..."

    apt install -y acl

    log_info "ACL installed successfully"
}

# Step 10: Create deployer user + give access /var/www to deployer user
create_deployer_user() {
    if id "deployer" &>/dev/null; then
        log_warn "User 'deployer' exists"
    else
        log_step "Create deployer user..."
        adduser --disabled-password --gecos "" deployer
        log_info "Give deployer user access to /var/www directory..."
        setfacl -R -m u:deployer:rwx /var/www
        log_info "Deployer user created successfully"
    fi
}

# Step 13: Create SSH Key Pair
create_ssh_key_pair() {
    log_step "Creating SSH Key Pair for deployer user..."

    # Run commands as deployer user without interactive shell
    sudo -u deployer mkdir -p /home/deployer/.ssh
    sudo -u deployer ssh-keygen -t ed25519 -C "Deploy web app with CI/CD" -N "" -f /home/deployer/.ssh/id_ed25519
    sudo -u deployer sh -c 'cd /home/deployer/.ssh && cat id_ed25519.pub >> authorized_keys'
    sudo -u deployer chmod 600 /home/deployer/.ssh/authorized_keys
    sudo -u deployer chmod 700 /home/deployer/.ssh

    log_info "SSH Key Pair created successfully"
}

# Display summary
show_summary() {
    echo ""
    echo -e "${GREEN}================================="
    echo -e "    INSTALLATION SUMMARY"
    echo -e "=================================${NC}"
    echo ""
    echo -e "✅ PHP and Laravel extensions installed"
    echo -e "✅ Nginx installed and running"
    echo -e "✅ Composer installed"
    echo -e "✅ Web directory created: /var/www"
    if [[ "$DB_ENGINE" == "mariadb" ]]; then
        echo -e "✅ MariaDB installed and configured"
    else
        echo -e "✅ PostgreSQL installed and configured"
    fi
    echo -e "✅ Database created: ${DB_NAME}"
    echo -e "✅ Database user created: ${DB_USER}"

    if [[ "$INSTALL_REDIS" == true ]]; then
        echo -e "✅ Redis installed and running"
    else
        echo -e "⏭️  Redis skipped (use --with-redis to install)"
    fi

    echo -e "✅ Certbot installed"
    echo -e "✅ ACL installed"
    echo -e "✅ Deployer user created"
    echo -e "✅ SSH Key Pair generated"
    echo ""
    echo -e "${YELLOW}Important Notes:${NC}"
    echo -e "• SSH public key location: /home/deployer/.ssh/id_ed25519.pub"
    if [[ "$DB_ENGINE" == "mariadb" ]]; then
        echo -e "• MariaDB connection details:"
        echo -e "  - Host: localhost"
        echo -e "  - Port: 3306"
    else
        echo -e "• PostgreSQL connection details:"
        echo -e "  - Host: localhost"
        echo -e "  - Port: 5432"
    fi
    echo -e "  - Database: ${DB_NAME}"
    echo -e "  - Username: ${DB_USER}"
    echo -e "  - Password: ${DB_PASS}"
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

    # Check if private key exists
    if [[ -f /home/deployer/.ssh/id_ed25519 ]]; then
        echo -e "${YELLOW}SSH Private Key:${NC}"
        echo -e "${GREEN}Copy this private key to your CI/CD system:${NC}"
        echo ""
        cat /home/deployer/.ssh/id_ed25519
        echo ""
        echo ""
    else
        log_error "SSH private key not found!"
    fi

    # SSH Host Key Scan
    echo -e "${YELLOW}Host Key Information:${NC}"
    echo -e "${GREEN}Add these to your known_hosts file or CI/CD system:${NC}"
    echo ""

    # Get server information
    local hostname=$(hostname -f 2>/dev/null || hostname)
    local ip_address=$(hostname -I | awk '{print $1}')

    # Scan for different key types
    for host in "localhost" "$hostname" "$ip_address"; do
        if [[ -n "$host" && "$host" != "localhost" ]] || [[ "$host" == "localhost" ]]; then
            echo "# Host keys for: $host"
            if command -v ssh-keyscan >/dev/null 2>&1; then
                ssh-keyscan -t ed25519 "$host" 2>/dev/null | head -10
            else
                log_warn "ssh-keyscan command not found"
            fi
            echo ""
        fi
    done

    echo -e "${BLUE}=================================${NC}"
    echo ""
}

# Main execution
main() {
    log_info "Starting Enhanced Laravel with Nginx PHP-FPM setup..."

    # Parse command line arguments
    parse_arguments "$@"

    # Validate required arguments
    validate_arguments

    # Display configuration
    echo ""
    echo -e "${BLUE}Configuration:${NC}"
    echo -e "• Database Engine: ${DB_ENGINE}"
    echo -e "• Database Name: ${DB_NAME}"
    echo -e "• Database User: ${DB_USER}"
    echo -e "• Database Password: ${DB_PASS}"
    echo -e "• Install Redis: ${INSTALL_REDIS}"
    echo ""

    # Confirm before proceeding
    read -p "Do you want to proceed with this configuration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled."
        exit 0
    fi

    check_root

    # Basic installation steps
    configure_ufw
    install_php
    install_nginx
    install_composer
    if [[ "$DB_ENGINE" == "mariadb" ]]; then
        install_mariadb
        configure_mariadb_database
    else
        install_postgresql
        configure_postgresql_database
    fi
    install_redis
    install_certbot
    install_acl
    create_deployer_user
    create_ssh_key_pair

    show_summary

    display_ssh_info
}

# Run main function
main "$@"
