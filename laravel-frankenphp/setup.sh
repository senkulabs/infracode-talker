#!/bin/bash

# Laravel with FrankenPHP Setup Script
# This script automates the installation of Laravel with FrankenPHP on Ubuntu

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
INSTALL_REDIS=false
SKIP_CADDYFILE=false
DB_ENGINE="postgresql"
DB_NAME=""
DB_USER=""
DB_PASS=""
REDIS_PASS=""
HOSTNAME=""

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
Laravel with FrankenPHP Setup Script

USAGE:
    $0 --hostname=DOMAIN --db-name=NAME --db-user=USER --db-pass=PASS [OPTIONS]

REQUIRED ARGUMENTS:
    --hostname=DOMAIN       Site hostname (e.g. gladion.app)
    --db-name=NAME          Database name
    --db-user=USER          Database user
    --db-pass=PASSWORD      Database password

OPTIONS:
    --db-engine=ENGINE      Database engine: postgresql (default) or mariadb
    --with-redis            Install Redis server
    --redis-pass=PASSWORD   Redis password (auto-generated if --with-redis but omitted)
    --skip-caddyfile        Skip creating the site Caddyfile
    --help                  Show this help message

EXAMPLES:
    $0 --hostname=gladion.app --db-name=myapp --db-user=myuser --db-pass=mypass
    $0 --hostname=gladion.app --db-name=myapp --db-user=myuser --db-pass=mypass --db-engine=mariadb
    $0 --hostname=gladion.app --db-name=myapp --db-user=myuser --db-pass=mypass --with-redis
    $0 --hostname=gladion.app --db-name=myapp --db-user=myuser --db-pass=mypass --skip-caddyfile

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
            --redis-pass=*)
                REDIS_PASS="${1#*=}"
                shift
                ;;
            --skip-caddyfile)
                SKIP_CADDYFILE=true
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
            --hostname=*)
                HOSTNAME="${1#*=}"
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

    if [[ -z "$HOSTNAME" ]]; then
        missing_args+=("--hostname")
    fi

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

apt_update() {
    log_step "Refreshing apt package index..."
    apt update -y
    log_info "apt index updated"
}

# Step 0: Configure UFW
configure_ufw() {
    log_step "Configuring UFW firewall..."
    ufw allow OpenSSH
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 443/udp
    ufw --force enable
    log_info "UFW enabled with OpenSSH, 80/tcp, 443/tcp, 443/udp allowed"
}

# Step 1: Install FrankenPHP
install_frankenphp() {
    log_step "Installing FrankenPHP..."
    curl https://frankenphp.dev/install.sh | sh

    if command -v frankenphp >/dev/null 2>&1; then
        log_info "FrankenPHP installed successfully: $(frankenphp version 2>/dev/null | head -n1)"
    else
        log_error "FrankenPHP installation failed"
        exit 1
    fi
}

# Step 2: Install PHP extensions (ZTS build required by FrankenPHP)
install_php_extensions() {
    log_step "Installing PHP extensions (php-zts-*)..."
    apt install -y \
        php-zts-mbstring \
        php-zts-bcmath \
        php-zts-gd \
        php-zts-intl \
        php-zts-zip \
        php-zts-curl \
        php-zts-xml \
        php-zts-sqlite3 \
        php-zts-pdo
    log_info "PHP extensions installed successfully"
}

# Step 3: Install Composer
install_composer() {
    log_step "Installing Composer..."
    curl -sLS https://getcomposer.org/installer | php -- --install-dir=/usr/bin/ --filename=composer
    log_info "Composer installed successfully"
}

# Step 4: Install PostgreSQL
install_postgresql() {
    log_info "Installing PostgreSQL..."
    apt install postgresql postgresql-contrib -y
    apt install -y php-zts-pgsql php-zts-pdo-pgsql

    systemctl start postgresql
    systemctl enable postgresql

    if systemctl is-active --quiet postgresql; then
        log_info "PostgreSQL installed and running successfully"
        log_info "PHP extensions installed: pgsql, pdo-pgsql"
        log_info "Default postgres user created. You can set password with: sudo -u postgres psql -c \"ALTER USER postgres PASSWORD 'your_password';\""
    else
        log_error "PostgreSQL failed to start"
        systemctl status postgresql
        exit 1
    fi
}

# Step 4: Configure PostgreSQL Database
configure_postgresql_database() {
    log_step "Configuring PostgreSQL database..."

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

# Step 3 (alt): Install MariaDB
install_mariadb() {
    log_info "Installing MariaDB..."
    apt install mariadb-server -y
    apt install -y php-zts-mysqli php-zts-pdo-mysql

    systemctl start mariadb
    systemctl enable mariadb

    if systemctl is-active --quiet mariadb; then
        log_info "MariaDB installed and running successfully"
        log_info "PHP extensions installed: mysqli, pdo-mysql"
    else
        log_error "MariaDB failed to start"
        systemctl status mariadb
        exit 1
    fi
}

# Step 4 (alt): Configure MariaDB Database
configure_mariadb_database() {
    log_step "Configuring MariaDB database..."

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

# Step 5: Install Redis (optional)
install_redis() {
    if [[ "$INSTALL_REDIS" == true ]]; then
        log_step "Installing Redis..."
        apt install redis-server -y
        apt install -y php-zts-redis

        # Auto-generate password if not supplied
        if [[ -z "$REDIS_PASS" ]]; then
            REDIS_PASS="$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)"
            log_info "Generated Redis password (no --redis-pass supplied)"
        fi

        # Set requirepass in /etc/redis/redis.conf (replace existing or append)
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
            log_info "Redis installed and running successfully"
            log_info "PHP extension installed: redis"
            if redis-cli -a "$REDIS_PASS" --no-auth-warning ping 2>/dev/null | grep -q PONG; then
                log_info "Redis is responding to authenticated ping"
            else
                log_error "Redis auth ping failed"
                exit 1
            fi
        else
            log_error "Redis failed to start"
            systemctl status redis-server
            exit 1
        fi
    else
        log_info "Skipping Redis installation (use --with-redis to install)"
    fi
}

# Step 6: Install ACL
install_acl() {
    log_step "Installing ACL (Access Control List)..."
    apt install -y acl
    log_info "ACL installed successfully"
}

# Step 7: Install Supervisor (process manager for Laravel queue workers / Horizon)
install_supervisor() {
    log_step "Installing Supervisor..."
    apt install -y supervisor

    systemctl enable supervisor
    systemctl start supervisor

    if systemctl is-active --quiet supervisor; then
        log_info "Supervisor installed and running successfully"
    else
        log_error "Supervisor failed to start"
        systemctl status supervisor
        exit 1
    fi
}

# Step 8: Create deployer user
create_deployer_user() {
    if id "deployer" &>/dev/null; then
        log_warn "User 'deployer' exists"
    else
        log_step "Create deployer user..."
        adduser --disabled-password --gecos "" deployer
        log_info "Deployer user created successfully"
    fi
}

# Step 9: Create SSH Key Pair for deployer user
create_ssh_key_pair() {
    log_step "Creating SSH Key Pair for deployer user..."

    sudo -u deployer mkdir -p /home/deployer/.ssh
    sudo -u deployer ssh-keygen -t ed25519 -C "Deploy web app with CI/CD" -N "" -f /home/deployer/.ssh/id_ed25519
    sudo -u deployer sh -c 'cd /home/deployer/.ssh && cat id_ed25519.pub >> authorized_keys'
    sudo -u deployer chmod 600 /home/deployer/.ssh/authorized_keys
    sudo -u deployer chmod 700 /home/deployer/.ssh

    log_info "SSH Key Pair created successfully"
}

# Step 10: Create www directory
create_www_dir() {
    log_step "Creating www directory"
    mkdir -p /var/www
    log_info "The www directory created"
}

# Step 11: Grant access deployer and frankenphp users to /var/www
grant_var_www_directory() {
    log_step "Grant access /var/www directory for deployer and frankenphp users"
    setfacl -R -m u:deployer:rwx -m d:u:deployer:rwx /var/www
    setfacl -R -m u:frankenphp:rwX -m d:u:frankenphp:rwX /var/www
    log_info "The access to /var/www directory has been granted."
}

# Step 12: Create site Caddyfile (optional)
create_site_caddyfile() {
    if [[ "$SKIP_CADDYFILE" == true ]]; then
        log_info "Skipping site Caddyfile creation (--skip-caddyfile)"
        return
    fi

    log_step "Creating site Caddyfile for ${HOSTNAME}..."

    mkdir -p /etc/frankenphp/Caddyfile.d

    cat > /etc/frankenphp/Caddyfile.d/${HOSTNAME}.caddyfile <<EOF
${HOSTNAME} {
    root * /var/www/${HOSTNAME}/current/public
    encode zstd br gzip
    php_server
}
EOF

    log_info "Site Caddyfile created at /etc/frankenphp/Caddyfile.d/${HOSTNAME}.caddyfile"
}

# Display summary
show_summary() {
    echo ""
    echo -e "${GREEN}================================="
    echo -e "    INSTALLATION SUMMARY"
    echo -e "=================================${NC}"
    echo ""
    echo -e "✅ FrankenPHP installed"
    echo -e "✅ PHP extensions installed (mbstring, bcmath, gd, intl, zip, curl, xml)"
    echo -e "✅ Composer installed"
    echo -e "✅ Web directory created: /var/www/${HOSTNAME}/public"
    if [[ "$DB_ENGINE" == "mariadb" ]]; then
        echo -e "✅ MariaDB installed and configured"
    else
        echo -e "✅ PostgreSQL installed and configured"
    fi
    echo -e "✅ Database created: ${DB_NAME}"
    echo -e "✅ Database user created: ${DB_USER}"

    if [[ "$INSTALL_REDIS" == true ]]; then
        echo -e "✅ Redis installed and running (password protected)"
    else
        echo -e "⏭️  Redis skipped (use --with-redis to install)"
    fi

    echo -e "✅ ACL installed"
    echo -e "✅ Supervisor installed and running"
    echo -e "✅ Deployer user created"
    echo -e "✅ Access to /var/www directory for deployer and frankenphp users has granted"
    echo -e "✅ Deployer passwordless sudo for supervisorctl: /etc/sudoers.d/deployer"
    echo -e "✅ SSH Key Pair generated"
    if [[ "$SKIP_CADDYFILE" == true ]]; then
        echo -e "⏭️  Site Caddyfile skipped (--skip-caddyfile)"
    else
        echo -e "✅ Site Caddyfile created: /etc/frankenphp/Caddyfile.d/${HOSTNAME}.caddyfile"
    fi
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
    if [[ "$INSTALL_REDIS" == true ]]; then
        echo -e "• Redis connection details:"
        echo -e "  - Host: 127.0.0.1"
        echo -e "  - Port: 6379"
        echo -e "  - Password: ${REDIS_PASS}"
    fi
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    if [[ "$SKIP_CADDYFILE" == true ]]; then
        echo -e "• Provide your own Caddyfile for ${HOSTNAME} (root: /var/www/${HOSTNAME}/public)"
    else
        echo -e "• Ensure /etc/frankenphp/Caddyfile imports Caddyfile.d/*.caddyfile"
    fi
    echo -e "• Start/reload FrankenPHP to apply site config"
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
        echo ""
    else
        log_error "SSH private key not found!"
    fi

    echo -e "${YELLOW}Host Key Information:${NC}"
    echo -e "${GREEN}Add these to your known_hosts file or CI/CD system:${NC}"
    echo ""

    local hostname=$(hostname -f 2>/dev/null || hostname)
    local ip_address=$(hostname -I | awk '{print $1}')

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
    log_info "Starting Laravel with FrankenPHP setup..."

    parse_arguments "$@"
    validate_arguments

    echo ""
    echo -e "${BLUE}Configuration:${NC}"
    echo -e "• Hostname: ${HOSTNAME}"
    echo -e "• Database Engine: ${DB_ENGINE}"
    echo -e "• Database Name: ${DB_NAME}"
    echo -e "• Database User: ${DB_USER}"
    echo -e "• Database Password: ${DB_PASS}"
    echo -e "• Install Redis: ${INSTALL_REDIS}"
    if [[ "$INSTALL_REDIS" == true ]]; then
        echo -e "• Redis Password: ${REDIS_PASS:-<auto-generated>}"
    fi
    echo -e "• Skip Caddyfile: ${SKIP_CADDYFILE}"
    echo ""

    read -p "Do you want to proceed with this configuration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled."
        exit 0
    fi

    check_root
    apt_update
    configure_ufw
    install_frankenphp
    install_php_extensions
    install_composer
    if [[ "$DB_ENGINE" == "mariadb" ]]; then
        install_mariadb
        configure_mariadb_database
    else
        install_postgresql
        configure_postgresql_database
    fi
    install_redis
    install_acl
    install_supervisor
    create_deployer_user
    create_ssh_key_pair
    create_www_dir
    grant_var_www_directory
    create_site_caddyfile

    show_summary
    display_ssh_info
}

# Run main function
main "$@"
