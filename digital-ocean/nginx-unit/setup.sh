#!/bin/bash

# Laravel with Nginx Unit Setup Script
# This script automates the installation of Laravel with Nginx Unit on Ubuntu

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
INSTALL_REDIS=false
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
Enhanced Laravel with Nginx Unit Setup Script

USAGE:
    $0 --db-name=NAME -db-user=USER --db-pass=PASS [OPTIONS]

REQUIRED ARGUMENTS:
    --db-name=NAME          Database name
    --db-user=USER          Database user
    --db-pass=PASSWORD      Database password

OPTIONS:
    --with-redis            Install Redis server
    --help                  Show this help message

EXAMPLES:
    $0 --db-name=myapp --db-user=myuser --db-pass=mypass
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

    # Create systemd override to make socket permissions persistent
    log_info "Creating systemd override for persistent socket permissions..."
    mkdir -p /etc/systemd/system/unit.service.d
    cat > /etc/systemd/system/unit.service.d/override.conf << 'EOF'
[Service]
ExecStartPost=/bin/chgrp unit /var/run/control.unit.sock
ExecStartPost=/bin/chmod 660 /var/run/control.unit.sock
EOF
    
    # Reload systemd and restart unit to apply the override
    systemctl daemon-reload
    systemctl restart unit
    
    # Verify socket permissions
    if [[ -S /var/run/control.unit.sock ]]; then
        local perms=$(stat -c "%a %U:%G" /var/run/control.unit.sock)
        log_info "Socket permissions set: $perms"
    else
        log_warn "Socket file not found after restart"
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

# Step 9: Install ACL
install_acl() {
    log_step "Installing ACL (Access Control List)..."

    apt install -y acl

    log_info "ACL installed successfully"
}

# Step 10: Create deployer user + give access to deployer user
create_deployer_user() {
    if id "deployer" &>/dev/null; then
        log_warn "User 'deployer' exists"
    else
        log_step "Create deployer user..."
        adduser --disabled-password --gecos "" deployer
        log_info "Give deployer user access to /var/www directory..."
        setfacl -R -m u:deployer:rwx /var/www
        log_info "Add deployer user to unit (nginx unit) group..."
        usermod -a -G unit deployer
        log_info "Deployer user created successfully"
    fi
}

# Step 11: Configure sudo access for deployer user
configure_deployer_sudo() {
    log_step "Configuring sudo access for deployer user..."

    # Create sudoers file for deployer user
    cat > /etc/sudoers.d/deployer << 'EOF'
# Allow deployer user to run specific commands without password
# Grant deployer user to access Control API Nginx Unit
deployer ALL=(ALL) NOPASSWD: /usr/bin/curl -X * --unix-socket /var/run/control.unit.sock *
# Grant deployer user to access certbot command
deployer ALL=(ALL) NOPASSWD: /usr/bin/certbot renew, /usr/bin/certbot certonly
EOF

    # Set proper permissions
    chmod 440 /etc/sudoers.d/deployer

    # Validate the sudoers file
    if visudo -cf /etc/sudoers.d/deployer; then
        log_info "Sudo configuration for deployer user created successfully"
    else
        log_error "Invalid sudoers configuration detected"
        rm -f /etc/sudoers.d/deployer
        exit 1
    fi
}

# Step 12: Configure Nginx Unit
configure_nginx_unit() {
    log_step "Configuring Nginx Unit HTTP for Laravel..."

    # Create the Nginx Unit configuration file
    cat > /home/deployer/unit-http.json << 'EOF'
{
    "listeners": {
        "*:80": {
            "pass": "routes"
        }
    },
    "routes": [
        {
            "match": {
                "uri": "/.well-known/acme-challenge/*"
            },
            "action": {
                "share": "/var/www/html/$uri"
            }
        },
        {
            "match": {
                "uri": "!/index.php"
            },
            "action": {
                "share": "/var/www/html/current/public$uri",
                "fallback": {
                    "pass": "applications/laravel"
                }
            }
        }
    ],
    "applications": {
        "laravel": {
            "type": "php",
            "root": "/var/www/html/current/public/",
            "script": "index.php",
            "user": "deployer",
            "group": "deployer"
        }
    }
}
EOF
chown deployer:deployer /home/deployer/unit-http.json

log_step "Configuring Nginx Unit HTTPS for Laravel..."

    # Create the Nginx Unit configuration file
    cat > /home/deployer/unit-https.json << 'EOF'
{
    "listeners": {
        "*:80": {
            "pass": "routes/redirect"
        },
        "*:443": {
            "pass": "routes/laravel",
            "tls": {
                "certificate": "bundle"
            }
        }
    },
    "routes": {
        "redirect": [
            {
                "match": {
                    "uri": "/.well-known/acme-challenge/*"
                },
                "action": {
                    "share": "/var/www/html/$uri"
                }
            },
            {
                "action": {
                    "return": 301,
                    "location": "https://$host$request_uri"
                }
            }
        ],
        "laravel": [
            {
                "match": {
                    "uri": "/.well-known/acme-challenge/*"
                },
                "action": {
                    "share": "/var/www/html/public$uri"
                }
            },
            {
                "match": {
                    "uri": "!/index.php"
                },
                "action": {
                    "share": "/var/www/html/current/public$uri",
                    "fallback": {
                        "pass": "applications/laravel"
                    }
                }
            }
        ]
    },
    "applications": {
        "laravel": {
            "type": "php",
            "root": "/var/www/html/current/public/",
            "script": "index.php",
            "user": "deployer",
            "group": "deployer"
        }
    }
}
EOF
chown deployer:deployer /home/deployer/unit-https.json
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
    echo -e "✅ Nginx Unit installed and running"
    echo -e "✅ Composer installed"
    echo -e "✅ Web directory created: /var/www"
    echo -e "✅ PostgreSQL installed and configured"
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
    echo -e "✅ Deployer sudo access configured"
    echo -e "✅ Configure Nginx Unit generated"
    echo -e "✅ SSH Key Pair generated"
    echo ""
    echo -e "${YELLOW}Important Notes:${NC}"
    echo -e "• SSH public key location: /home/deployer/.ssh/id_ed25519.pub"
    echo -e "• PostgreSQL connection details:"
    echo -e "  - Host: localhost"
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
    log_info "Starting Enhanced Laravel with Nginx Unit setup..."

    # Parse command line arguments
    parse_arguments "$@"

    # Validate required arguments
    validate_arguments

    # Display configuration
    echo ""
    echo -e "${BLUE}Configuration:${NC}"
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
    install_php
    install_nginx_unit
    install_composer
    create_web_directory
    install_postgresql
    configure_postgresql_database
    install_redis
    install_certbot
    install_acl
    create_deployer_user
    configure_deployer_sudo
    configure_nginx_unit
    create_ssh_key_pair

    show_summary

    display_ssh_info
}

# Run main function
main "$@"