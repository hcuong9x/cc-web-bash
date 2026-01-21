#!/bin/bash

# Script to clone WordPress site using Webinoly on Ubuntu 22.04
# Usage: ./clone-template.sh <domain> <GOOGLE_FILE_ID>

# Check if required parameters are provided
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 <domain> [GOOGLE_FILE_ID]"
    echo "Example with Google Drive: $0 example.com 1a2b3c4d5e6f7g8h9i0j"
    echo "Example with local file: $0 example.com"
    echo "Note: If FILE_ID is not provided, script will look for .wpress file in script directory"
    exit 1
fi

DOMAIN=$1
FILE_ID=$2
BACKUP_FILE="${DOMAIN}.wpress"
TEMP_DIR="/tmp/wp-restore-${DOMAIN}"
SCRIPT_DIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
EXTENSION_ZIP="$SCRIPT_DIR/all-in-one-wp-migration-url-extension.zip"

echo "=========================================="
echo "WordPress Site Clone Script"
echo "Domain: $DOMAIN"
if [ -n "$FILE_ID" ]; then
    echo "Google File ID: $FILE_ID"
else
    echo "Mode: Using local .wpress file"
fi
echo "=========================================="

# Create temporary directory
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR" || exit 1

# Step 1 & 2: Get backup file (from Google Drive or local)
if [ -n "$FILE_ID" ]; then
    # Download from Google Drive
    echo "[1/7] Checking gdown installation..."
    if ! command -v gdown &> /dev/null; then
        echo "gdown not found. Installing gdown..."
        sudo apt-get update
        sudo apt-get install -y python3-pip
        pip3 install gdown
        export PATH="$HOME/.local/bin:$PATH"
    fi

    echo "[2/7] Downloading backup file from Google Drive..."
    gdown "https://drive.google.com/uc?id=${FILE_ID}" -O "$BACKUP_FILE"

    if [ ! -f "$BACKUP_FILE" ]; then
        echo "Error: Failed to download backup file"
        exit 1
    fi

    echo "Backup file downloaded successfully: $BACKUP_FILE"
else
    # Use local .wpress file
    echo "[1/7] Skipping gdown installation (using local file)..."
    echo "[2/7] Looking for .wpress file in script directory..."
    
    # Find .wpress file in script directory
    LOCAL_WPRESS=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.wpress" -type f | head -n 1)
    
    if [ -z "$LOCAL_WPRESS" ]; then
        echo "Error: No .wpress file found in $SCRIPT_DIR"
        echo "Please place a .wpress backup file in the script directory"
        exit 1
    fi
    
    echo "Found local backup file: $(basename "$LOCAL_WPRESS")"
    cp "$LOCAL_WPRESS" "$TEMP_DIR/$BACKUP_FILE"
    
    if [ ! -f "$TEMP_DIR/$BACKUP_FILE" ]; then
        echo "Error: Failed to copy backup file"
        exit 1
    fi
    
    echo "Backup file copied successfully: $BACKUP_FILE"
fi

# Step 3: Check if WordPress site exists
echo "[3/7] Checking if WordPress site exists..."
WP_PATH="/var/www/$DOMAIN/htdocs"

if [ ! -d "$WP_PATH" ]; then
    echo "Error: WordPress site not found at $WP_PATH"
    echo "Please create the site first using: sudo site $DOMAIN -wp"
    exit 1
fi

if [ ! -f "/var/www/$DOMAIN/wp-config.php" ]; then
    echo "Error: wp-config.php not found. Site may not be properly configured."
    exit 1
fi

echo "WordPress site found at $WP_PATH"

# Step 4: Install All-in-One WP Migration plugin
echo "[4/7] Installing All-in-One WP Migration plugin..."
WP_PATH="/var/www/$DOMAIN/htdocs"
OWNER_GROUP=$(stat -c "%U:%G" "$WP_PATH")

# Delete all old plugins first
echo "Removing old plugins..."
cd "$WP_PATH" || exit 1
wp plugin delete --all --allow-root 2>/dev/null || true

# Install All-in-One WP Migration
echo "Installing All-in-One WP Migration plugin..."
wp plugin install all-in-one-wp-migration --activate --allow-root

if [ $? -ne 0 ]; then
    echo "Error: Failed to install All-in-One WP Migration plugin"
    exit 1
fi

sudo chown -R "$OWNER_GROUP" "$WP_PATH/wp-content/plugins/all-in-one-wp-migration/"
sudo chmod -R 755 "$WP_PATH/wp-content/plugins/all-in-one-wp-migration/"

# Step 5: Install All-in-One WP Migration URL Extension
echo "[5/7] Installing All-in-One WP Migration URL Extension..."

# Check if extension zip file exists
if [ ! -f "$EXTENSION_ZIP" ]; then
    echo "Error: Extension file not found at $EXTENSION_ZIP"
    echo "Please ensure all-in-one-wp-migration-url-extension.zip is in the script directory"
    exit 1
fi

# Deactivate and delete if already exists
cd "$WP_PATH" || exit 1
if wp plugin is-active all-in-one-wp-migration-url-extension --allow-root 2>/dev/null; then
    echo "Deactivating existing URL extension..."
    wp plugin deactivate all-in-one-wp-migration-url-extension --allow-root
fi

wp plugin delete all-in-one-wp-migration-url-extension --allow-root 2>/dev/null || true

# Install from zip file
echo "Installing URL extension from file..."
wp plugin install "$EXTENSION_ZIP" --activate --allow-root

if [ $? -ne 0 ]; then
    echo "Error: Failed to install URL Extension"
    exit 1
fi

EXT_DIR="$WP_PATH/wp-content/plugins/all-in-one-wp-migration-url-extension/"
sudo chown -R "$OWNER_GROUP" "$EXT_DIR"
sudo chmod -R 755 "$EXT_DIR"

# Step 6: Copy backup file to WordPress directory
echo "[6/7] Copying backup file..."
UPLOAD_DIR="$WP_PATH/wp-content/ai1wm-backups"
sudo mkdir -p "$UPLOAD_DIR"
sudo cp "$TEMP_DIR/$BACKUP_FILE" "$UPLOAD_DIR/"
sudo chown -R www-data:www-data "$UPLOAD_DIR"
sudo chmod 755 "$UPLOAD_DIR"

echo "Backup file copied to: $UPLOAD_DIR/$BACKUP_FILE"

# Step 7: Restore the backup
echo "[7/7] Restoring WordPress backup..."

# Get the backup filename
cd "$UPLOAD_DIR" || exit 1
LATEST_BACKUP="$(ls -1t *.wpress 2>/dev/null | head -n1)"

if [ -z "$LATEST_BACKUP" ]; then
    echo "Error: No backup file found in $UPLOAD_DIR"
    exit 1
fi

echo "Found backup file: $LATEST_BACKUP"
echo "Starting restore process..."

# Restore using WP-CLI
cd "$WP_PATH" || exit 1
wp ai1wm restore "$LATEST_BACKUP" --allow-root

if [ $? -ne 0 ]; then
    echo "Error: Failed to restore backup"
    exit 1
fi

echo "Restore completed successfully!"

# Remove backup file after successful restore
echo "Cleaning up backup file..."
sudo rm -rf "$UPLOAD_DIR"/*.wpress

# Set proper permissions
sudo chown -R www-data:www-data "$WP_PATH"
sudo find "$WP_PATH" -type d -exec chmod 755 {} \;
sudo find "$WP_PATH" -type f -exec chmod 644 {} \;

# Clean up
echo ""
echo "Cleaning up temporary files..."
cd /
rm -rf "$TEMP_DIR"

echo ""
echo "=========================================="
echo "WordPress site setup completed!"
echo "Domain: $DOMAIN"
echo "WordPress Admin: https://$DOMAIN/wp-admin"
echo "=========================================="
echo ""
echo "Note: If SSL is not configured, use http:// instead of https://"
echo ""

exit 0
