#!/bin/bash
# Odoo 12 Full Server Setup — Ubuntu 20.04 LTS
# Run as root: bash setup.sh <your-domain-or-IP>

set -e

DOMAIN=${1:-"localhost"}
ODOO_VERSION="12.0"
ODOO_USER="odoo"
ODOO_HOME="/opt/odoo"
ODOO_HOME_EXT="/opt/odoo/odoo-server"
ADDONS_PATH="/opt/odoo/custom-addons"
ODOO_CONFIG="/etc/odoo/odoo.conf"
ODOO_LOG="/var/log/odoo/odoo.log"
DB_PASSWORD=$(openssl rand -base64 16)
ADMIN_PASSWD=$(openssl rand -base64 16)

echo "============================================"
echo " Odoo 12 Setup on Ubuntu 20.04"
echo " Domain: $DOMAIN"
echo "============================================"

# --- 1. System Update ---
apt-get update && apt-get upgrade -y
apt-get install -y git curl wget python3-pip python3-dev python3-venv \
    libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev libldap2-dev build-essential \
    libssl-dev libffi-dev libmysqlclient-dev libjpeg-dev libpq-dev liblcms2-dev \
    libblas-dev libatlas-base-dev npm node-less xfonts-75dpi xfonts-base \
    postgresql postgresql-client nginx certbot python3-certbot-nginx

# --- 2. wkhtmltopdf 0.12.5 (required for PDF reports) ---
echo "Installing wkhtmltopdf..."
wget -q https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.focal_amd64.deb
dpkg -i wkhtmltox_0.12.5-1.focal_amd64.deb || apt-get install -f -y
rm wkhtmltox_0.12.5-1.focal_amd64.deb

# --- 3. PostgreSQL Setup ---
echo "Configuring PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql
su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD '$DB_PASSWORD';\""
su - postgres -c "createuser --createdb --username postgres --no-createrole --no-superuser $ODOO_USER 2>/dev/null || true"

# --- 4. Odoo System User ---
echo "Creating odoo user..."
adduser --system --quiet --shell=/bin/bash --home=$ODOO_HOME --gecos 'Odoo' --group $ODOO_USER 2>/dev/null || true

# --- 5. Install Odoo 12 from Source ---
echo "Cloning Odoo 12..."
mkdir -p $ODOO_HOME_EXT
git clone --depth 1 --branch $ODOO_VERSION https://github.com/odoo/odoo.git $ODOO_HOME_EXT

# --- 6. Python Virtual Environment ---
echo "Setting up Python virtual environment..."
python3 -m venv $ODOO_HOME/venv
source $ODOO_HOME/venv/bin/activate
pip install --upgrade pip wheel
pip install -r $ODOO_HOME_EXT/requirements.txt
deactivate

# --- 7. Custom Addons ---
echo "Setting up custom addons..."
mkdir -p $ADDONS_PATH
git clone https://github.com/loomoni/jtem.git $ADDONS_PATH/jtem
chown -R $ODOO_USER:$ODOO_USER $ADDONS_PATH

# --- 8. Odoo Configuration ---
echo "Writing Odoo config..."
mkdir -p /etc/odoo
mkdir -p /var/log/odoo

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

# --- 9. Systemd Service ---
echo "Installing systemd service..."
cp /opt/odoo/custom-addons/jtem/deploy/odoo12.service /etc/systemd/system/odoo12.service
systemctl daemon-reload
systemctl enable odoo12
systemctl start odoo12

# --- 10. Nginx Reverse Proxy ---
echo "Configuring Nginx..."
cp /opt/odoo/custom-addons/jtem/deploy/nginx.conf /etc/nginx/sites-available/odoo
sed -i "s/YOUR_DOMAIN/$DOMAIN/g" /etc/nginx/sites-available/odoo
ln -sf /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/odoo
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

# --- 11. SSL (skip for IP-only deployments) ---
if [ "$DOMAIN" != "localhost" ] && [[ "$DOMAIN" != *"."* ]] || [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Skipping SSL — domain required for Let's Encrypt"
else
    certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m loomonimorwo1@gmail.com
fi

echo ""
echo "============================================"
echo " SETUP COMPLETE"
echo " Odoo URL   : http://$DOMAIN"
echo " Master Pass: $ADMIN_PASSWD"
echo " DB Password: $DB_PASSWORD  (postgres user)"
echo " SAVE THESE CREDENTIALS!"
echo "============================================"
echo ""
echo "Next: run restore_db.sh to import your database."
