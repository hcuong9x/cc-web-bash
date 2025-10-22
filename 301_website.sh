#!/bin/bash

# ============================================================
# Clone a WordPress site using All-in-One WP Migration
# For Webinoly-managed sites
# Usage: ./clone-site.sh olddomain.com newdomain.com
# ============================================================

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 old_domain new_domain"
    exit 1
fi

old_domain=$1
new_domain=$2

# Webinoly path convention
domain_old_path="/var/www/$old_domain/htdocs"
domain_new_path="/var/www/$new_domain/htdocs"

# Local plugin zip paths
script_dir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
extension_zip="$script_dir/all-in-one-wp-migration-url-extension.zip"
simple_redirect_zip="$script_dir/simple-website-redirect.zip"

# Ensure paths exist
if [ ! -d "$domain_old_path" ]; then
    echo "❌ Error: Old domain path not found: $domain_old_path"
    exit 1
fi

if [ ! -d "$domain_new_path" ]; then
    echo "❌ Error: New domain path not found: $domain_new_path"
    exit 1
fi

# Helper function to run wp with root permission
wp_cli() {
    echo "➡️  Command: wp --allow-root --path=$1 ${@:2}"
    wp --allow-root --path="$1" "${@:2}"
}

backup_domain() {
    local domain_path="$1"
    local domain="$2"
    local backup_dir="$domain_path/wp-content/ai1wm-backups"

    echo "🧩 Preparing backup for $domain ..."

    cd "$domain_path" || return 1

    # Ensure plugin installed
    if ! wp_cli "$domain_path" plugin is-active all-in-one-wp-migration; then
        echo "Installing and activating all-in-one-wp-migration..."
        wp_cli "$domain_path" plugin install all-in-one-wp-migration --activate
    fi

    # Install / activate extension
    wp_cli "$domain_path" plugin delete all-in-one-wp-migration-url-extension
    wp_cli "$domain_path" plugin install "$extension_zip" --activate

    # mkdir -p "$backup_dir"
    # Remove old backups
    rm -rf "$backup_dir"/*.wpress

    echo "📦 Creating backup..."
    wp_cli "$domain_path" ai1wm backup --exclude-cache

    latest_backup=$(ls -1t "$backup_dir"/*.wpress 2>/dev/null | head -n1)
    if [ -z "$latest_backup" ]; then
        echo "❌ Backup failed for $domain"
        exit 1
    fi

    setup_owner "$domain_path"

    echo "✅ Backup created: $latest_backup"
    echo "Backup Size: $(du -sh "$backup_dir"/*.wpress)"
}

restore_domain() {
    local domain_path="$1"
    local domain="$2"

    echo "🔁 Restoring backup to $domain ..."

    cd "$domain_path" || return 1

    # Install plugin
    if ! wp_cli "$domain_path" plugin is-active all-in-one-wp-migration; then
        wp_cli "$domain_path" plugin install all-in-one-wp-migration --activate

    fi

    wp_cli "$domain_path" plugin delete all-in-one-wp-migration-url-extension
    wp_cli "$domain_path" plugin install "$extension_zip" --activate

    setup_owner "$domain_path"

    # Move backup file from old site
    echo "Moving backup file..."
    mv /var/www/$old_domain/htdocs/wp-content/ai1wm-backups/*.wpress "$domain_path/wp-content/ai1wm-backups/" 2>/dev/null

    latest_backup=$(ls -1t "$domain_path/wp-content/ai1wm-backups"/*.wpress 2>/dev/null | head -n1)
    if [ -z "$latest_backup" ]; then
        echo "❌ No backup found for restore."
        exit 1
    fi
    echo "Using backup file: ";
    echo $(basename "$latest_backup");
    backup_dir="$domain_path/wp-content/ai1wm-backups"
    latest_backup="$(ls -1t "$backup_dir"/*.wpress | head -n1)"
    
    wp ai1wm restore "$(basename "$latest_backup")" --allow-root
    echo "✅ Restore completed for $domain"

    # Clean up
    rm -rf "$domain_path/wp-content/ai1wm-backups"/*.wpress
    wp_cli "$domain_path" plugin deactivate all-in-one-wp-migration-url-extension
    wp_cli "$domain_path" plugin delete all-in-one-wp-migration-url-extension
    wp_cli "$domain_path" plugin deactivate all-in-one-wp-migration
    wp_cli "$domain_path" plugin delete all-in-one-wp-migration
}

setup_owner() {
    local domain_path="$1"
    local backup_dir="$domain_path/wp-content/ai1wm-backups"
    local plugin_aio_dir="$domain_path/wp-content/plugins/all-in-one-wp-migration"
    local plugin_aio_url_dir="$domain_path/wp-content/plugins/all-in-one-wp-migration-url-extension"

    sudo chown -R www-data:www-data "$plugin_aio_dir"
    sudo find "$plugin_aio_dir" -type d -exec chmod 755 {} \;
    sudo find "$plugin_aio_dir" -type f -exec chmod 644 {} \;

    sudo chown -R www-data:www-data "$plugin_aio_url_dir"
    sudo find "$plugin_aio_url_dir" -type d -exec chmod 755 {} \;
    sudo find "$plugin_aio_url_dir" -type f -exec chmod 644 {} \;

    sudo chown -R www-data:www-data "$backup_dir"
    sudo find "$backup_dir" -type d -exec chmod 755 {} \;
    sudo find "$backup_dir" -type f -exec chmod 644 {} \;

    echo "✅ Ownership and permissions set"

}
config_redirect() {
    local domain_path="$1"
    local domain="$2"

    echo "➡️ Setting redirect from $old_domain → $new_domain"

    wp_cli "$domain_path" plugin delete simple-website-redirect
    wp_cli "$domain_path" plugin install "$simple_redirect_zip" --activate

    wp_cli "$domain_path" option update simple_website_redirect_url "https://$new_domain"
    wp_cli "$domain_path" option update simple_website_redirect_type 301
    wp_cli "$domain_path" option update simple_website_redirect_status 1

    echo "✅ Redirect configured"
}

# -------------------------------------------------------------
# Run process
# -------------------------------------------------------------
echo "=============================="
echo "🌍 Cloning $old_domain → $new_domain"
echo "=============================="

backup_domain "$domain_old_path" "$old_domain"
restore_domain "$domain_new_path" "$new_domain"
config_redirect "$domain_old_path" "$old_domain"

echo "🎉 Clone completed successfully!"
