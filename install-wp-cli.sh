#!/bin/bash

# Script to install WP-CLI on Ubuntu
# WP-CLI is the command-line interface for WordPress

echo "=========================================="
echo "WP-CLI Installation Script"
echo "=========================================="

# Check if WP-CLI is already installed
if command -v wp &> /dev/null; then
    echo "WP-CLI is already installed:"
    wp --version
    read -p "Do you want to reinstall/update? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    echo "Updating WP-CLI..."
fi

# Step 1: Download WP-CLI
echo "[1/5] Downloading WP-CLI..."
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar

if [ ! -f "wp-cli.phar" ]; then
    echo "Error: Failed to download wp-cli.phar"
    exit 1
fi

# Step 2: Check if it works
echo "[2/5] Testing WP-CLI..."
php wp-cli.phar --info

if [ $? -ne 0 ]; then
    echo "Error: WP-CLI test failed. PHP may not be installed or configured correctly."
    rm -f wp-cli.phar
    exit 1
fi

# Step 3: Make it executable
echo "[3/5] Making WP-CLI executable..."
chmod +x wp-cli.phar

# Step 4: Move to global location
echo "[4/5] Installing WP-CLI globally..."
sudo mv wp-cli.phar /usr/local/bin/wp

if [ $? -ne 0 ]; then
    echo "Error: Failed to move WP-CLI to /usr/local/bin/wp"
    exit 1
fi

# Step 5: Verify installation
echo "[5/5] Verifying installation..."
wp --info

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "WP-CLI installed successfully!"
    echo "=========================================="
    echo "Version: $(wp --version)"
    echo "Path: $(which wp)"
    echo ""
    echo "You can now use 'wp' command to manage WordPress sites."
    echo "Example: wp plugin list --allow-root"
    echo "=========================================="
else
    echo "Error: Installation verification failed"
    exit 1
fi

exit 0

