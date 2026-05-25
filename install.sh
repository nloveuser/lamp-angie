#!/usr/bin/env bash
# LAMP-style stack: Angie + PHP 8.4-FPM + MariaDB + Auto SSL (ACME built-in)
# Supported: Ubuntu 22.04/24.04, Debian 12
# Run as root
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/nloveuser/lamp-angie/refs/heads/main/install.sh)
#
# version: 1.0.0
# change-log:
#   1.0.0 - Initial release

set -euo pipefail

PHP_VER="8.4"
DB_ROOT_PASS="${DB_ROOT_PASS:-$(openssl rand -base64 16)}"
WEBROOT="/var/www/html"
ACME_EMAIL=""
DOMAIN=""

SCRIPT_VERSION="1.0.0"
SCRIPT_CHANGELOG="1.0.0 - Initial release"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] && die "Run as root"

echo -e "${GREEN}install-lamp-angie${NC} v${SCRIPT_VERSION}"
echo ""

# ── Detect distro ─────────────────────────────────────────────────────────────
. /etc/os-release
DISTRO="${ID}"
CODENAME="${VERSION_CODENAME}"
[[ "${DISTRO}" =~ ^(ubuntu|debian)$ ]] || die "Unsupported distro: ${DISTRO}"
info "Distro: ${DISTRO} ${CODENAME}"

# ── Interactive prompts ───────────────────────────────────────────────────────
echo ""
read -rp "  Domain name (e.g. example.com): " DOMAIN
[[ -z "${DOMAIN}" ]] && die "Domain cannot be empty"

read -rp "  Email for Let's Encrypt: " ACME_EMAIL
[[ -z "${ACME_EMAIL}" ]] && die "Email cannot be empty"

echo ""
info "Domain: ${DOMAIN} | Email: ${ACME_EMAIL}"
echo ""

# ── Base deps ─────────────────────────────────────────────────────────────────
info "Installing base deps..."
apt-get update -qq > /dev/null 2>&1
apt-get install -y -qq curl ca-certificates > /dev/null 2>&1

# ── Angie ─────────────────────────────────────────────────────────────────────
info "Adding Angie repo..."
curl -fsSL https://angie.software/keys/angie-signing.gpg \
  -o /etc/apt/trusted.gpg.d/angie-signing.gpg

# Official format from angie.software/angie/docs/installation/oss_packages/
# deb https://download.angie.software/angie/<ID>/<VERSION_ID> <VERSION_CODENAME> main
echo "deb https://download.angie.software/angie/${DISTRO}/${VERSION_ID} ${CODENAME} main" \
  > /etc/apt/sources.list.d/angie.list

apt-get update -qq
info "Installing Angie..."
apt-get install -y -qq angie

# ── PHP 8.4 ───────────────────────────────────────────────────────────────────
info "Adding ondrej/php repo (PHP ${PHP_VER})..."
if [[ "${DISTRO}" == "ubuntu" ]]; then
  apt-get install -y -qq software-properties-common > /dev/null 2>&1
  add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1
else
  curl -fsSL https://packages.sury.org/php/apt.gpg \
    | gpg --dearmor -o /usr/share/keyrings/sury-php.gpg 2>/dev/null
  echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] \
https://packages.sury.org/php/ ${CODENAME} main" \
    > /etc/apt/sources.list.d/sury-php.list
fi

apt-get update -qq > /dev/null 2>&1
info "Installing PHP ${PHP_VER}-FPM + modules..."
apt-get install -y -qq \
  "php${PHP_VER}-fpm" "php${PHP_VER}-cli" \
  "php${PHP_VER}-mysql" "php${PHP_VER}-mbstring" \
  "php${PHP_VER}-xml" "php${PHP_VER}-curl" \
  "php${PHP_VER}-zip" "php${PHP_VER}-gd" \
  "php${PHP_VER}-bcmath" "php${PHP_VER}-intl" \
  "php${PHP_VER}-opcache" > /dev/null 2>&1

# ── MariaDB ───────────────────────────────────────────────────────────────────
info "Installing MariaDB..."
apt-get install -y -qq mariadb-server > /dev/null 2>&1

info "Securing MariaDB..."
# MariaDB fresh install uses unix_socket auth — connect via sudo mysql
mysql_exec() { mysql --user=root "$@" 2>/dev/null; }

mysql_exec -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${DB_ROOT_PASS}');" \
  || mysql_exec -e "UPDATE mysql.user SET Password=PASSWORD('${DB_ROOT_PASS}') WHERE User='root';"
mysql_exec -e "DELETE FROM mysql.user WHERE User='';"
mysql_exec -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');"
mysql_exec -e "DROP DATABASE IF EXISTS test;"
mysql_exec -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql_exec -e "FLUSH PRIVILEGES;"

# ── fastcgi-php snippet ───────────────────────────────────────────────────────
PHP_SOCK="/run/php/php${PHP_VER}-fpm.sock"

mkdir -p /etc/angie/snippets
cat > /etc/angie/snippets/fastcgi-php.conf <<'EOF'
fastcgi_split_path_info ^(.+?\.php)(/.*)$;
try_files $fastcgi_script_name =404;
set $path_info $fastcgi_path_info;
fastcgi_param PATH_INFO $path_info;
include fastcgi_params;
fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
EOF

# ── ACME dir ──────────────────────────────────────────────────────────────────
ACME_DIR="/etc/angie/acme"
mkdir -p "${ACME_DIR}"
chown -R www-data:www-data "${ACME_DIR}"

# ── Angie config ──────────────────────────────────────────────────────────────
info "Writing Angie config..."

# Remove default config if exists
rm -f /etc/angie/http.d/default.conf

cat > "/etc/angie/http.d/${DOMAIN}.conf" <<EOF
# ACME account — shared across all server blocks
acme_client main_acme https://acme-v02.api.letsencrypt.org/directory
    email ${ACME_EMAIL}
    path  ${ACME_DIR};

# HTTP — redirect to HTTPS + serve ACME challenges
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};

    location /.well-known/acme-challenge/ {
        root ${WEBROOT};
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name ${DOMAIN} www.${DOMAIN};

    ssl_certificate     \$acme_cert main_acme;
    ssl_certificate_key \$acme_cert_key main_acme;

    acme main_acme;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    root ${WEBROOT};
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# ── Test page ─────────────────────────────────────────────────────────────────
echo "<?php phpinfo();" > "${WEBROOT}/info.php"
chown www-data:www-data "${WEBROOT}/info.php"

# ── Services ──────────────────────────────────────────────────────────────────
info "Enabling services..."
systemctl enable --now mariadb > /dev/null 2>&1
systemctl enable --now "php${PHP_VER}-fpm" > /dev/null 2>&1
angie -t > /dev/null 2>&1 && systemctl enable --now angie > /dev/null 2>&1

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Installation complete!${NC}"
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo -e "  Script:   v${SCRIPT_VERSION}"
echo -e "  Angie:    $(angie -v 2>&1 | head -1)"
echo -e "  PHP:      $(php${PHP_VER} -r 'echo PHP_VERSION;')"
echo -e "  MariaDB:  $(mysql --version | awk '{print $1,$2,$3}')"
echo ""
echo -e "  Domain:   https://${DOMAIN}"
echo -e "  phpinfo:  https://${DOMAIN}/info.php"
echo ""
echo -e "${YELLOW}  DB root password: ${DB_ROOT_PASS}${NC}"
echo -e "${YELLOW}  Save it! Remove /info.php after testing.${NC}"
echo -e ""
echo -e "  SSL cert will be issued automatically on first request."
echo -e "  Make sure DNS A-record for ${DOMAIN} points to this server."
echo -e "${GREEN}══════════════════════════════════════════${NC}"
