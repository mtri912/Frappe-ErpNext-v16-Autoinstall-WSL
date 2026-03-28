#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# ============================================================
# COLOR CODES
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ============================================================
# BANNER
# ============================================================
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "        Frappe & ERPNext v16 Auto-Installer (WSL/Ubuntu)       "
echo "        Stack: MariaDB 11.8 | Python 3.14 | Node 24 | uv/nvm   "
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ============================================================
# GENERATE UNIQUE INSTALL ID
# ============================================================
UNIQUE_ID=$(date +%s%N | sha256sum | head -c 8)
echo -e "${BLUE}Install ID: ${YELLOW}${UNIQUE_ID}${NC}"

# ============================================================
# PASSWORD PROMPT FUNCTIONS
# ============================================================
prompt_for_mariadb_password() {
    while true; do
        echo -ne "${YELLOW}Enter MariaDB root password:${NC} "
        read -s mariadb_password
        echo
        echo -ne "${YELLOW}Confirm MariaDB root password:${NC} "
        read -s mariadb_password_confirm
        echo
        if [ "$mariadb_password" = "$mariadb_password_confirm" ]; then
            break
        else
            echo -e "${RED}Passwords do not match. Try again.${NC}"
        fi
    done
}

prompt_for_admin_password() {
    while true; do
        echo -ne "${YELLOW}Enter Frappe administrator password:${NC} "
        read -s admin_password
        echo
        echo -ne "${YELLOW}Confirm Frappe administrator password:${NC} "
        read -s admin_password_confirm
        echo
        if [ "$admin_password" = "$admin_password_confirm" ]; then
            break
        else
            echo -e "${RED}Passwords do not match. Try again.${NC}"
        fi
    done
}

# ============================================================
# ROOT CHECK
# ============================================================
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root. Please use: sudo bash install.sh${NC}"
    exit 1
fi

# ============================================================
# USER SETUP
# ============================================================
echo -ne "${YELLOW}Do you want to create a new user? (yes/no):${NC} "
read create_user
if [ "$create_user" = "yes" ]; then
    echo -ne "${YELLOW}Enter the new username:${NC} "
    read new_username
    if id "$new_username" &>/dev/null; then
        echo -e "${YELLOW}User '$new_username' already exists. Using it.${NC}"
    else
        adduser "$new_username"
        usermod -aG sudo "$new_username"
        echo -e "${GREEN}User '$new_username' created and added to sudo group.${NC}"
    fi
    username="$new_username"
else
    # Detect the real user even when running under sudo
    username="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"
fi

if [ -z "$username" ] || [ "$username" = "root" ]; then
    echo -e "${RED}Could not determine a non-root username."
    echo -e "Please run as: sudo -u <your_user> bash install.sh${NC}"
    exit 1
fi

echo -e "${GREEN}Installing for user: ${YELLOW}${username}${NC}"

# ============================================================
# COLLECT ALL INPUTS UPFRONT
# ============================================================
prompt_for_mariadb_password
prompt_for_admin_password

echo -ne "${YELLOW}Enter the site name (e.g. mysite.localhost):${NC} "
read site_name

echo -ne "${YELLOW}Install ERPNext v16? (yes/no):${NC} "
read install_erpnext

echo -ne "${YELLOW}Install HRMS v16? (yes/no):${NC} "
read install_hrms

# ============================================================
# EXPORT ALL VARIABLES (needed in sudo -E subshells)
# ============================================================
BENCH_NAME="frappe-bench16_${UNIQUE_ID}"
USER_HOME="/home/${username}"

export username mariadb_password admin_password site_name
export install_erpnext install_hrms UNIQUE_ID
export BENCH_NAME USER_HOME

echo -e "\n${CYAN}Summary:"
echo -e "  User       : ${YELLOW}${username}${CYAN}"
echo -e "  Bench dir  : ${YELLOW}${USER_HOME}/${BENCH_NAME}${CYAN}"
echo -e "  Site name  : ${YELLOW}${site_name}${CYAN}"
echo -e "  ERPNext    : ${YELLOW}${install_erpnext}${CYAN}"
echo -e "  HRMS       : ${YELLOW}${install_hrms}${NC}"
echo ""

# ============================================================
# PHASE 1: SYSTEM UPDATE & CORE PACKAGES
# ============================================================
echo -e "${BLUE}━━━ Phase 1/9: System Update & Core Packages ━━━${NC}"
apt-get update -y
apt-get upgrade -y
apt-get install -y \
    git curl wget nano \
    redis-server \
    pkg-config \
    libmariadb-dev \
    gcc build-essential \
    xvfb libfontconfig \
    apt-transport-https lsb-release gnupg \
    ca-certificates software-properties-common \
    cron
echo -e "${GREEN}Core packages installed.${NC}"

# Start Redis — handle both systemd and non-systemd WSL
if systemctl is-system-running --wait 2>/dev/null | grep -qE "running|degraded"; then
    systemctl enable redis-server
    systemctl restart redis-server
else
    service redis-server start || true
fi

# ============================================================
# PHASE 2: MARIADB 11.8
# ============================================================
echo -e "\n${BLUE}━━━ Phase 2/9: MariaDB 11.8 ━━━${NC}"

# Add official MariaDB 11.8 repository
echo -e "${BLUE}Adding MariaDB 11.8 official repository...${NC}"
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup -o /tmp/mariadb_repo_setup
chmod +x /tmp/mariadb_repo_setup
/tmp/mariadb_repo_setup --mariadb-server-version="mariadb-11.8"
rm /tmp/mariadb_repo_setup
apt-get update -y
apt-get install -y mariadb-server mariadb-client mariadb-backup

echo -e "${CYAN}Installed: $(mariadb --version 2>&1)${NC}"

# Apply Frappe-specific MariaDB configuration
echo -e "${BLUE}Applying Frappe MariaDB config...${NC}"
cat > /etc/mysql/mariadb.conf.d/99-frappe.cnf << 'MARIADBCNF'
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
MARIADBCNF

# Start MariaDB — handle both systemd (WSL2 with systemd) and non-systemd WSL
echo -e "${BLUE}Starting MariaDB...${NC}"
if systemctl is-system-running --wait 2>/dev/null | grep -qE "running|degraded"; then
    systemctl enable mariadb
    systemctl restart mariadb
    echo -e "${GREEN}MariaDB started via systemctl.${NC}"
else
    service mariadb start || true
    sleep 3
    echo -e "${GREEN}MariaDB started via service.${NC}"
fi

# Secure MariaDB installation (automated, no interactive prompts)
echo -e "${BLUE}Securing MariaDB...${NC}"
mariadb_password_sql="${mariadb_password//\'/\\\'}"
mysql -u root << SQLEOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${mariadb_password_sql}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQLEOF

echo -e "${GREEN}MariaDB 11.8 installed and secured.${NC}"

# ============================================================
# PHASE 3: WKHTMLTOPDF
# ============================================================
echo -e "\n${BLUE}━━━ Phase 3/9: wkhtmltopdf ━━━${NC}"
cd /tmp

# Step 1: Install libssl1.1 (required on Ubuntu 24.04 — dropped from default repos)
echo -e "${BLUE}Installing libssl1.1 dependency...${NC}"
wget -q http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb
dpkg -i libssl1.1_1.1.1f-1ubuntu2_amd64.deb
rm libssl1.1_1.1.1f-1ubuntu2_amd64.deb

# Step 2: Download & install wkhtmltopdf 0.12.6 (jammy build — works on Ubuntu 24.04 with the above fix)
echo -e "${BLUE}Installing wkhtmltopdf 0.12.6...${NC}"
wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb
# First attempt may fail due to missing dependencies — fix and retry
dpkg -i wkhtmltox_0.12.6.1-3.jammy_amd64.deb || apt-get --fix-broken install -y
dpkg -i wkhtmltox_0.12.6.1-3.jammy_amd64.deb
rm wkhtmltox_0.12.6.1-3.jammy_amd64.deb

cd - > /dev/null
echo -e "${GREEN}wkhtmltopdf $(wkhtmltopdf --version 2>&1 | head -1) installed.${NC}"

# ============================================================
# PHASE 4: REDIS OPTIMIZATIONS
# ============================================================
echo -e "\n${BLUE}━━━ Phase 4/9: Redis Optimizations ━━━${NC}"
# /sys/kernel/mm may be read-only in WSL — skip gracefully
echo 'never' | tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null 2>&1 \
    || echo -e "${YELLOW}  Note: transparent_hugepage skipped (WSL restriction).${NC}"
sysctl -w vm.overcommit_memory=1 2>/dev/null || true
sysctl -w net.core.somaxconn=511 2>/dev/null || true
# Persist in sysctl.conf (idempotent)
grep -qxF 'vm.overcommit_memory = 1' /etc/sysctl.conf \
    || echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf
grep -qxF 'net.core.somaxconn = 511' /etc/sysctl.conf \
    || echo 'net.core.somaxconn = 511' >> /etc/sysctl.conf
echo -e "${GREEN}Redis optimizations applied.${NC}"

# ============================================================
# PHASE 5: NODE.JS 24 VIA NVM  (runs as target user)
# ============================================================
echo -e "\n${BLUE}━━━ Phase 5/9: Node.js 24 via NVM (user: ${username}) ━━━${NC}"

# Quoted heredoc — all $ variables expand inside the user's shell
sudo -H -u "$username" bash << 'NODEEOF'
set -e
export NVM_DIR="$HOME/.nvm"

echo "  Installing NVM..."
curl -fsSo- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

# Load NVM in this session (no .bashrc sourcing needed)
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

echo "  Installing Node.js 24..."
nvm install 24
nvm use 24
nvm alias default 24

echo "  Updating npm..."
npm install -g npm@latest

echo "  Installing yarn..."
npm install -g yarn

echo "  Node  : $(node -v)"
echo "  npm   : $(npm -v)"
echo "  yarn  : $(yarn -v)"
NODEEOF

echo -e "${GREEN}Node.js 24 installed via NVM.${NC}"

# ============================================================
# PHASE 6: PYTHON 3.14 + BENCH CLI VIA UV  (runs as target user)
# ============================================================
echo -e "\n${BLUE}━━━ Phase 6/9: Python 3.14 + Bench CLI via UV (user: ${username}) ━━━${NC}"

# Quoted heredoc — runs entirely in user context
sudo -H -u "$username" bash << 'UVEOF'
set -e
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

echo "  Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh | sh

# Reload PATH after uv install
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

echo "  Installing Python 3.14..."
uv python install 3.14

echo "  Installing frappe-bench..."
uv tool install frappe-bench --python python3.14

# Ensure uv tool bin is in PATH
export PATH="$HOME/.local/bin:$PATH"

echo "  bench version: $(bench --version)"
UVEOF

echo -e "${GREEN}Python 3.14 and bench CLI installed via UV.${NC}"

# ============================================================
# PHASE 7: BENCH INIT  (runs as target user)
# ============================================================
echo -e "\n${BLUE}━━━ Phase 7/9: Initialize Frappe Bench v16 ━━━${NC}"

# Unquoted heredoc — ${BENCH_NAME} expands from outer (root) env
# \$HOME, \$NVM_DIR expand inside the user's shell
sudo -H -E -u "$username" bash << BENCHINIT
set -e
export NVM_DIR="\$HOME/.nvm"
export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"

cd "\$HOME"
echo "  Initializing bench: ${BENCH_NAME}..."
bench init ${BENCH_NAME} \
    --frappe-branch version-16 \
    --python python3.14

echo "  Bench initialized at \$HOME/${BENCH_NAME}"
BENCHINIT

echo -e "${GREEN}Frappe bench v16 initialized at ${USER_HOME}/${BENCH_NAME}.${NC}"

# ============================================================
# PHASE 8: CREATE SITE  (runs as target user)
# ============================================================
echo -e "\n${BLUE}━━━ Phase 8/9: Create Site: ${site_name} ━━━${NC}"

# Passwords are passed via -E (exported env), accessed as \$ in inner shell
# This avoids quoting issues with special characters in passwords
sudo -H -E -u "$username" bash << SITEEOF
set -e
export NVM_DIR="\$HOME/.nvm"
export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"

cd "\$HOME/${BENCH_NAME}"

echo "  Creating site: ${site_name}..."
bench new-site "${site_name}" \
    --db-root-password "${mariadb_password}" \
    --admin-password "${admin_password}"

bench use "${site_name}"
bench enable-scheduler
bench set-config developer_mode 1
bench --site "${site_name}" set-maintenance-mode off
bench --site "${site_name}" clear-cache

echo "  Site '${site_name}' ready."
SITEEOF

echo -e "${GREEN}Site '${site_name}' created successfully.${NC}"

# ============================================================
# PHASE 9: INSTALL APPS  (runs as target user)
# ============================================================
echo -e "\n${BLUE}━━━ Phase 9/9: Install Apps ━━━${NC}"

if [ "$install_erpnext" = "yes" ]; then
    echo -e "${BLUE}Installing ERPNext v16...${NC}"
    sudo -H -E -u "$username" bash << ERPEOF
set -e
export NVM_DIR="\$HOME/.nvm"
export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"

cd "\$HOME/${BENCH_NAME}"
bench get-app --branch version-16 erpnext
bench --site "${site_name}" install-app erpnext
echo "  ERPNext v16 installed."
ERPEOF
    echo -e "${GREEN}ERPNext v16 installed.${NC}"
else
    echo -e "${YELLOW}Skipping ERPNext installation.${NC}"
fi

if [ "$install_hrms" = "yes" ]; then
    echo -e "${BLUE}Installing HRMS v16...${NC}"
    sudo -H -E -u "$username" bash << HRMSEOF
set -e
export NVM_DIR="\$HOME/.nvm"
export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"

cd "\$HOME/${BENCH_NAME}"
bench get-app --branch version-16 hrms
bench --site "${site_name}" install-app hrms
echo "  HRMS v16 installed."
HRMSEOF
    echo -e "${GREEN}HRMS v16 installed.${NC}"
else
    echo -e "${YELLOW}Skipping HRMS installation.${NC}"
fi

# ============================================================
# DONE
# ============================================================
echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "              Installation Complete!"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Bench     : ${YELLOW}${USER_HOME}/${BENCH_NAME}${NC}"
echo -e "${GREEN}  Site      : ${YELLOW}${site_name}${NC}"
echo -e "${GREEN}  User      : ${YELLOW}${username}${NC}"
echo ""
echo -e "${CYAN}To start the development server:${NC}"
echo -e "${YELLOW}  sudo su - ${username}"
echo -e "  cd ~/${BENCH_NAME}"
echo -e "  bench start${NC}"
echo ""
echo -e "${CYAN}Then open in your Windows browser:${NC}"
echo -e "${YELLOW}  http://localhost:8000${NC}"
echo ""
echo -e "${CYAN}Tip: Store all project files inside WSL (${USER_HOME}/...)."
echo -e "     Avoid /mnt/c/... paths — they are significantly slower.${NC}"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
