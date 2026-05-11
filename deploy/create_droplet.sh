#!/bin/bash
# Create DigitalOcean Droplet for Odoo 12
# Requires: doctl authenticated with your DO API token
# Usage: bash create_droplet.sh <do-api-token> [domain]

set -e

DO_TOKEN=${1:?"Usage: $0 <digitalocean-api-token> [domain]"}
DOMAIN=${2:-""}
DROPLET_NAME="jtem-odoo12"
REGION="ams3"          # Amsterdam — closest to East Africa with good latency
SIZE="s-2vcpu-4gb"     # 2 vCPU, 4GB RAM, 80GB SSD — $24/month
IMAGE="ubuntu-20-04-x64"
SSH_KEY_NAME="jtem-deploy-key"

export DIGITALOCEAN_ACCESS_TOKEN=$DO_TOKEN

# Install doctl if not available
if ! command -v doctl &> /dev/null; then
    echo "Installing doctl..."
    wget -q https://github.com/digitalocean/doctl/releases/download/v1.104.0/doctl-1.104.0-linux-amd64.tar.gz
    tar xf doctl-1.104.0-linux-amd64.tar.gz
    mv doctl /usr/local/bin
    rm doctl-1.104.0-linux-amd64.tar.gz
fi

doctl auth init -t $DO_TOKEN

# Generate SSH key for this deployment
if [ ! -f ~/.ssh/jtem_deploy ]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/jtem_deploy -N "" -C "jtem-odoo12-deploy"
fi

# Upload SSH key to DigitalOcean
echo "Uploading SSH key to DigitalOcean..."
KEY_ID=$(doctl compute ssh-key import $SSH_KEY_NAME \
    --public-key-file ~/.ssh/jtem_deploy.pub \
    --format ID --no-header 2>/dev/null || \
    doctl compute ssh-key list --format Name,ID --no-header | grep $SSH_KEY_NAME | awk '{print $2}')

echo "Using SSH Key ID: $KEY_ID"

# Create the droplet
echo "Creating droplet '$DROPLET_NAME'..."
DROPLET_ID=$(doctl compute droplet create $DROPLET_NAME \
    --image $IMAGE \
    --size $SIZE \
    --region $REGION \
    --ssh-keys $KEY_ID \
    --wait \
    --format ID --no-header)

echo "Droplet created. ID: $DROPLET_ID"

# Get droplet IP
sleep 10
DROPLET_IP=$(doctl compute droplet get $DROPLET_ID --format PublicIPv4 --no-header)
echo "Droplet IP: $DROPLET_IP"

# Save connection info
cat > droplet_info.txt <<EOF
Droplet Name : $DROPLET_NAME
Droplet ID   : $DROPLET_ID
IP Address   : $DROPLET_IP
SSH Key      : ~/.ssh/jtem_deploy
SSH Command  : ssh -i ~/.ssh/jtem_deploy root@$DROPLET_IP
Region       : $REGION
Size         : $SIZE
Created      : $(date)
EOF

echo ""
echo "============================================"
echo " Droplet ready!"
echo " IP: $DROPLET_IP"
echo " SSH: ssh -i ~/.ssh/jtem_deploy root@$DROPLET_IP"
echo "============================================"
echo ""
echo "Next steps:"
echo "1. Wait ~30s then: ssh -i ~/.ssh/jtem_deploy root@$DROPLET_IP"
echo "2. Copy setup.sh to server and run: bash setup.sh $DROPLET_IP"
echo "3. Upload dump file and run: bash restore_db.sh /tmp/jtem_2026-05-05_13-49-39.dump jtem"

# Optionally auto-run setup on server
read -p "Run setup automatically on the server now? [y/N] " CONFIRM
if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
    echo "Waiting for server to be ready..."
    sleep 30
    ssh -i ~/.ssh/jtem_deploy -o StrictHostKeyChecking=no root@$DROPLET_IP \
        "curl -sSL https://raw.githubusercontent.com/loomoni/jtem/main/deploy/setup.sh | bash -s -- $DROPLET_IP"
fi
