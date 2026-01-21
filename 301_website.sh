#!/bin/bash

# Check if the correct number of parameters are passed
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 old_domain new_domain [slug]"
    exit 1
fi

# Assign parameters to variables
old_domain=$1
new_domain=$2
slug=${3:-htdocs}  # Default to 'htdocs' if not provided

# Define the old domain path
domain_old_path="/var/www/$old_domain/$slug"
# Define the new domain path
domain_new_path="/var/www/$new_domain/$slug"

script_dir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
extension_zip="$script_dir/all-in-one-wp-migration-url-extension.zip"
simple_website_redirect_plugin_zip="$script_dir/simple-website-redirect.zip" 
echo "$extension_zip"

# Define the backup_domain function
backup_domain() {
    local domain_path="$1"
    local domain=$(basename "$(dirname "$domain_path")") # Extract domain name
    local owner_group=$(stat -c "%U:%G" "$domain_path")
    
    cd "$domain_path" || {
        echo "Directory not found: $domain_path"
        return
    }
    echo "$domain_path"
    echo "$domain"
    echo "$owner_group"

    echo "Start for $domain"

    if ! wp --allow-root plugin is-active all-in-one-wp-migration; then
        # Check if the plugin is installed
        if ! wp --allow-root plugin is-installed all-in-one-wp-migration; then
            # Install and activate the plugin
            echo "Install and activate all-in-one-wp-migration"
            wp --allow-root plugin install all-in-one-wp-migration --activate
        else
            # Activate the plugin if it's installed but not active
            echo "Activate all-in-one-wp-migration"
            wp --allow-root plugin update all-in-one-wp-migration
            wp --allow-root plugin activate all-in-one-wp-migration
        fi
        sudo chown -R "$owner_group" /var/www/"$domain"/"$slug"/wp-content/plugins/all-in-one-wp-migration/
        sudo chmod -R 755 /var/www/"$domain"/"$slug"/wp-content/plugins/all-in-one-wp-migration/
    else
        wp --allow-root plugin update all-in-one-wp-migration
        echo "all-in-one-wp-migration is already active"
    fi

    local ext_dir="/var/www/$domain/$slug/wp-content/plugins/all-in-one-wp-migration-url-extension/"
    if wp --allow-root plugin is-active all-in-one-wp-migration-url-extension; then
        # Check if the unlimited extension is installed
        echo "all-in-one-wp-migration-url-extension is already active"
        wp --allow-root plugin deactivate all-in-one-wp-migration-url-extension
    fi
    wp --allow-root plugin delete all-in-one-wp-migration-url-extension
    wp --allow-root plugin install "$extension_zip" --activate
    sudo chown -R "$owner_group" "$ext_dir"
    sudo chmod -R 755 "$ext_dir"

    echo "Start backup for $domain"
    backup_dir="/var/www/$domain/$slug/wp-content/ai1wm-backups"
    # remove older backup
    sudo rm -rf "$backup_dir"/*.wpress

    wp ai1wm backup --sites --allow-root --exclude-cache
    echo "Backup Size: $(du -sh "$backup_dir"/*.wpress)"
    
    # Get the latest backup filename
    cd "$backup_dir" || exit
    latest_backup="$(ls -1t | head -n1)"

    if [ $? -ne 0 ]; then
        echo "Failed to create backup for $domain"
    fi

    # Uninstall the All-in-One WP Migration plugins
    # wp --allow-root plugin deactivate all-in-one-wp-migration-url-extension
    # wp --allow-root plugin delete all-in-one-wp-migration-url-extension

    # wp --allow-root plugin deactivate all-in-one-wp-migration
    # wp --allow-root plugin delete all-in-one-wp-migration
}

# Define the restore_domain function
restore_domain() {
    local domain_path="$1"
    local domain=$(basename "$(dirname "$domain_path")") # Extract domain name
    local owner_group=$(stat -c "%U:%G" "$domain_path")
    echo "Restoring $domain"

    cd "$domain_path" || {
        echo "Directory not found: $domain_path"
        return
    }

    echo "$domain_path"
    echo "$domain"
    echo "$owner_group"

    if ! wp --allow-root plugin is-active all-in-one-wp-migration; then
        # Check if the plugin is installed
        if ! wp --allow-root plugin is-installed all-in-one-wp-migration; then
            # Install and activate the plugin
            echo "Install and activate all-in-one-wp-migration"
            wp --allow-root plugin install all-in-one-wp-migration --activate
        else
            # Activate the plugin if it's installed but not active
            echo "Activate all-in-one-wp-migration"
            wp --allow-root plugin update all-in-one-wp-migration
            wp --allow-root plugin activate all-in-one-wp-migration
        fi
        sudo chown -R "$owner_group" /var/www/"$domain"/"$slug"/wp-content/plugins/all-in-one-wp-migration/
        sudo chmod -R 755 /var/www/"$domain"/"$slug"/wp-content/plugins/all-in-one-wp-migration/
    else
        wp --allow-root plugin update all-in-one-wp-migration
        echo "all-in-one-wp-migration is already active"
    fi

    local ext_dir="/var/www/$domain/$slug/wp-content/plugins/all-in-one-wp-migration-url-extension/"
    if wp --allow-root plugin is-active all-in-one-wp-migration-url-extension; then
        # Check if the unlimited extension is installed
        echo "all-in-one-wp-migration-url-extension is already active"
        wp --allow-root plugin deactivate all-in-one-wp-migration-url-extension
    fi
    wp --allow-root plugin delete all-in-one-wp-migration-url-extension
    wp --allow-root plugin install "$extension_zip" --activate
    sudo chown -R "$owner_group" "$ext_dir"
    sudo chmod -R 755 "$ext_dir"

    echo "move backup file"
    mv "$domain_old_path/wp-content/ai1wm-backups/"*.wpress "$domain_new_path/wp-content/ai1wm-backups/"
    
    local ai1wm_dir="/var/www/$domain/$slug/wp-content/ai1wm-backups"
    sudo chown -R "$owner_group" "$ai1wm_dir"
    sudo chmod -R 755 "$ai1wm_dir"
    # Perform the restore
    backup_dir="/var/www/$domain/$slug/wp-content/ai1wm-backups"
    latest_backup="$(ls -1t "$backup_dir"/*.wpress | head -n1)"
    
    echo "file backup $latest_backup"

    if [ -z "$latest_backup" ]; then
        echo "No backup file found to restore for $domain"
        return
    fi
    latest_backup_name=$(basename "$latest_backup")
    wp ai1wm restore "$latest_backup_name" --allow-root
    echo "Restore completed for $domain"

    # remove older backup
    sudo rm -rf "$backup_dir"/*.wpress

    # Uninstall the All-in-One WP Migration plugins after restore
    wp --allow-root plugin deactivate all-in-one-wp-migration-url-extension
    wp --allow-root plugin delete all-in-one-wp-migration-url-extension

    wp --allow-root plugin deactivate all-in-one-wp-migration
    wp --allow-root plugin delete all-in-one-wp-migration

    echo "Update owner $owner_group $domain_new_path"
    sudo chown -R $owner_group $domain_new_path
}

config_redirect() {

    cd "$domain_old_path"

    wp --allow-root plugin deactivate all-in-one-wp-migration-url-extension
    wp --allow-root plugin deactivate all-in-one-wp-migration

    wp --allow-root plugin delete simple-website-redirect
    wp --allow-root plugin install "$simple_website_redirect_plugin_zip" --activate

    local owner_group=$(stat -c "%U:%G" "$domain_old_path")
    sudo chown -R $owner_group "$domain_old_path/wp-content/plugins/simple-website-redirect"

    # Set the redirection configurations in wp_options table
    wp --allow-root option update simple_website_redirect_url "https://$new_domain"
    wp --allow-root option update simple_website_redirect_type 301
    wp --allow-root option update simple_website_redirect_status 1

    echo "Redirection configured: $old_domain --> $new_domain"
}


# Check if the old domain path exists
if [ -d "$domain_old_path" ]; then
    echo "Step 1: Found the directory for the old domain at $domain_old_path"
    # Call the backup_domain function
    backup_domain "$domain_old_path"
else
    echo "Error: Directory $domain_old_path does not exist!"
    exit 1
fi

# Create the new domain directory if it doesn't exist
if [ -d "$domain_new_path" ]; then
    echo "Step 2: Found the directory for the new domain at $domain_new_path"
    restore_domain "$domain_new_path"
    config_redirect "$domain_old_path" "$domain_new_path"
else
    echo "Error: Directory $domain_new_path does not exist!"
    exit 1
fi