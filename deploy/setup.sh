#!/bin/bash
# Odoo 12 Full Server Setup — Ubuntu 22.04 LTS
# Run as root: bash setup.sh <your-domain-or-IP>

set -e

DOMAIN=${1:-"159.223.166.245"}
ODOO_VERSION="12.0"
ODOO_USER="odoo"
ODOO_HOME="/opt/odoo"
ODOO_HOME_EXT="/opt/odoo/odoo-server"
ADDONS_PATH="/opt/odoo/custom-addons"
ODOO_CONFIG="/etc/odoo/odoo.conf"
ODOO_LOG="/var/log/odoo/odoo.log"
ADMIN_PASSWD=$(openssl rand -base64 16)

echo "============================================"
echo " Odoo 12 Setup — Ubuntu 22.04"
echo " Domain/IP: $DOMAIN"
echo "============================================"

# --- 1. System Update ---
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y
apt-get install -y software-properties-common curl wget git gnupg2 \
    libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev libldap2-dev build-essential \
    libssl-dev libffi-dev libjpeg-dev libpq-dev liblcms2-dev \
    node-less npm xfonts-75dpi xfonts-base fontconfig

# --- 2. Python 3.8 (Odoo 12 is incompatible with Python 3.10) ---
echo "Installing Python 3.8..."
add-apt-repository ppa:deadsnakes/ppa -y
apt-get update
apt-get install -y python3.8 python3.8-dev python3.8-venv python3.8-distutils
curl -sS https://bootstrap.pypa.io/pip/3.8/get-pip.py | python3.8

# --- 3. PostgreSQL ---
echo "Installing PostgreSQL..."
apt-get install -y postgresql postgresql-client
systemctl start postgresql
systemctl enable postgresql

# --- 4. Swap File (2GB RAM is tight for Odoo) ---
if [ ! -f /swapfile ]; then
    echo "Creating 2GB swap file..."
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# --- 5. wkhtmltopdf 0.12.6.1 for Ubuntu 22.04 ---
echo "Installing wkhtmltopdf..."
wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
dpkg -i wkhtmltox_0.12.6.1-2.jammy_amd64.deb || apt-get install -f -y
rm -f wkhtmltox_0.12.6.1-2.jammy_amd64.deb

# --- 6. Odoo System User & PostgreSQL User ---
echo "Creating system users..."
adduser --system --quiet --shell=/bin/bash --home=$ODOO_HOME --gecos 'Odoo' --group $ODOO_USER 2>/dev/null || true
su - postgres -c "createuser --createdb $ODOO_USER 2>/dev/null || true"

# --- 7. Odoo 12 Source ---
echo "Cloning Odoo 12 (this takes a few minutes)..."
git clone --depth 1 --branch $ODOO_VERSION https://github.com/odoo/odoo.git $ODOO_HOME_EXT

# --- 8. Python Virtual Environment ---
echo "Setting up Python 3.8 virtual environment..."
python3.8 -m venv $ODOO_HOME/venv
source $ODOO_HOME/venv/bin/activate
pip install --upgrade pip wheel
pip install -r $ODOO_HOME_EXT/requirements.txt
# Fix for Python 3.8 compatibility with some packages
pip install Pillow==9.5.0 gevent==21.12.0 greenlet==1.1.3
deactivate

# --- 9. Custom Addons from GitHub ---
echo "Cloning JTEM custom addons..."
mkdir -p $ADDONS_PATH
git clone https://github.com/loomoni/jtem.git $ADDONS_PATH/jtem
chown -R $ODOO_USER:$ODOO_USER $ADDONS_PATH

# --- 10. Odoo Configuration ---
echo "Writing Odoo configuration..."
mkdir -p /etc/odoo /var/log/odoo

cat > $ODOO_CONFIG <<EOF
[options]
admin_passwd = $ADMIN_PASSWD
db_host = localhost
db_port = 5432
db_user = $ODOO_USER
db_password = False
addons_path = $ODOO_HOME_EXT/addons,$ADDONS_PATH/jtem
logfile = $ODOO_LOG
log_level = info
xmlrpc_port = 8069
workers = 2
max_cron_threads = 1
limit_memory_hard = 1677721600
limit_memory_soft = 629145600
limit_request = 8192
limit_time_cpu = 600
limit_time_real = 1200
EOF

chown $ODOO_USER:$ODOO_USER $ODOO_CONFIG
chmod 640 $ODOO_CONFIG
chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME
chown -R $ODOO_USER:$ODOO_USER /var/log/odoo

# --- 11. Systemd Service ---
echo "Installing systemd service..."
cat > /etc/systemd/system/odoo12.service <<EOF
[Unit]
Description=Odoo 12 Service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo12
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_HOME/venv/bin/python3 $ODOO_HOME_EXT/odoo-bin \\
    --config=$ODOO_CONFIG \\
    --logfile=$ODOO_LOG
StandardOutput=journal+console
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable odoo12
systemctl start odoo12

# --- 12. Nginx Reverse Proxy ---
echo "Configuring Nginx..."
apt-get install -y nginx

cat > /etc/nginx/sites-available/odoo <<'NGINXEOF'
upstream odoo {
    server 127.0.0.1:8069;
}
upstream odoo-chat {
    server 127.0.0.1:8072;
}
server {
    listen 80;
    server_name _;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;
    client_max_body_size 200m;

    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;

    access_log /var/log/nginx/odoo.access.log;
    error_log  /var/log/nginx/odoo.error.log;

    location /longpolling {
        proxy_pass http://odoo-chat;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    location / {
        proxy_pass http://odoo;
        proxy_redirect off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    location ~* /web/static/ {
        expires 864000;
        proxy_pass http://odoo;
        proxy_set_header Host $host;
    }
    gzip on;
    gzip_types text/plain application/javascript text/xml text/css;
}
NGINXEOF

ln -sf /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/odoo
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx
systemctl enable nginx

# --- Done ---
echo ""
echo "============================================"
echo " SETUP COMPLETE"
echo " Odoo URL    : http://$DOMAIN"
echo " Master Pass : $ADMIN_PASSWD"
echo " SAVE THE MASTER PASSWORD ABOVE!"
echo "============================================"
echo ""
echo "Status check:"
systemctl status odoo12 --no-pager -l | tail -20
echo ""
echo "Next: upload your .dump file and run:"
echo "  bash /opt/odoo/custom-addons/jtem/deploy/restore_db.sh /tmp/jtem.dump jtem"
