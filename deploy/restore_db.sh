#!/bin/bash
# Restore JTEM Odoo 12 PostgreSQL database
# Usage: bash restore_db.sh <path-to-dump-file> [db-name]

set -e

DUMP_FILE=${1:?"Usage: $0 <dump-file> [db-name]"}
DB_NAME=${2:-"jtem"}
ODOO_USER="odoo"

if [ ! -f "$DUMP_FILE" ]; then
    echo "Error: dump file not found: $DUMP_FILE"
    echo "Upload it first with (run on YOUR Windows machine):"
    echo "  scp \"D:\\Lmoney Documents\\Erico Group\\JTEM\\jtem_2026-05-05_13-49-39.dump\" root@159.223.166.245:/tmp/jtem.dump"
    exit 1
fi

echo "Stopping Odoo..."
systemctl stop odoo12 2>/dev/null || true

echo "Dropping existing database '$DB_NAME' (if any)..."
su - postgres -c "dropdb --if-exists $DB_NAME"

echo "Creating database '$DB_NAME' owned by '$ODOO_USER'..."
su - postgres -c "createdb -O $ODOO_USER $DB_NAME"

echo "Restoring dump file: $DUMP_FILE"
# Try custom format first, fall back to plain SQL
su - postgres -c "pg_restore -d $DB_NAME -v --no-owner --no-acl '$DUMP_FILE'" 2>/dev/null || \
    su - postgres -c "psql -d $DB_NAME -f '$DUMP_FILE'"

echo "Disabling outbound email (safety measure)..."
su - postgres -c "psql $DB_NAME -c \"UPDATE ir_mail_server SET active=false;\"" 2>/dev/null || true
su - postgres -c "psql $DB_NAME -c \"UPDATE fetchmail_server SET active=false;\"" 2>/dev/null || true

echo "Setting db_name in Odoo config..."
if grep -q "^db_name" /etc/odoo/odoo.conf; then
    sed -i "s/^db_name.*/db_name = $DB_NAME/" /etc/odoo/odoo.conf
else
    echo "db_name = $DB_NAME" >> /etc/odoo/odoo.conf
fi

echo "Starting Odoo..."
systemctl start odoo12

sleep 5
echo ""
echo "============================================"
echo " Database '$DB_NAME' restored!"
echo " Visit: http://159.223.166.245"
echo " Logs : journalctl -u odoo12 -f"
echo "============================================"
