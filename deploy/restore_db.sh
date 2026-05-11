#!/bin/bash
# Restore JTEM Odoo 12 database from .dump file
# Usage: bash restore_db.sh <path-to-dump-file> [db-name]
# Example: bash restore_db.sh /tmp/jtem_2026-05-05_13-49-39.dump jtem

set -e

DUMP_FILE=${1:?"Usage: $0 <dump-file> [db-name]"}
DB_NAME=${2:-"jtem"}
ODOO_USER="odoo"

if [ ! -f "$DUMP_FILE" ]; then
    echo "Error: dump file '$DUMP_FILE' not found."
    exit 1
fi

echo "Stopping Odoo service..."
systemctl stop odoo12 2>/dev/null || true

echo "Dropping existing database '$DB_NAME' (if any)..."
su - postgres -c "dropdb --if-exists $DB_NAME"

echo "Creating database '$DB_NAME'..."
su - postgres -c "createdb -O $ODOO_USER $DB_NAME"

echo "Restoring from $DUMP_FILE ..."
su - postgres -c "pg_restore -d $DB_NAME -v --no-owner --no-privileges '$DUMP_FILE'" || \
    su - postgres -c "psql $DB_NAME < '$DUMP_FILE'"

echo "Neutralizing database (resetting email/SMTP to prevent accidental sends)..."
su - postgres -c "psql $DB_NAME -c \"UPDATE ir_mail_server SET active=false;\""
su - postgres -c "psql $DB_NAME -c \"UPDATE fetchmail_server SET active=false;\" 2>/dev/null || true"

echo "Updating Odoo config to use database '$DB_NAME'..."
if ! grep -q "^db_name" /etc/odoo/odoo.conf; then
    echo "db_name = $DB_NAME" >> /etc/odoo/odoo.conf
else
    sed -i "s/^db_name.*/db_name = $DB_NAME/" /etc/odoo/odoo.conf
fi

echo "Starting Odoo service..."
systemctl start odoo12

echo ""
echo "============================================"
echo " Database '$DB_NAME' restored successfully"
echo " Odoo is starting at http://localhost:8069"
echo " Check logs: journalctl -u odoo12 -f"
echo "============================================"
