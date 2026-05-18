#!/bin/bash

# Script to clone WordPress sites using Webinoly on Ubuntu 22.04
#
# Usage:
#   ./clone-template.sh <domain1> [domain2 ...] [backup.wpress]
#   ./clone-template.sh --file backup.wpress <domain1> [domain2 ...]
#   ./clone-template.sh --google-file-id <GOOGLE_FILE_ID> <domain1> [domain2 ...]
#
# Examples:
#   ./clone-template.sh domain1.com domain2.com domain3.com file.wpress
#   ./clone-template.sh --file file.wpress domain1.com domain2.com
#   ./clone-template.sh example.com

set -o pipefail

SCRIPT_DIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
EXTENSION_ZIP="$SCRIPT_DIR/all-in-one-wp-migration-url-extension.zip"
GOOGLE_FILE_ID=""
WPRESS_FILE=""
BACKUP_SOURCE=""
SOURCE_TEMP_DIR=""
DOMAINS=()
SUCCESS_DOMAINS=()
FAILED_DOMAINS=()

usage() {
    cat <<EOF
Usage:
  $0 <domain1> [domain2 ...] [backup.wpress]
  $0 --file backup.wpress <domain1> [domain2 ...]
  $0 --google-file-id GOOGLE_FILE_ID <domain1> [domain2 ...]

Examples:
  $0 domain1.com domain2.com domain3.com file.wpress
  $0 --file file.wpress domain1.com domain2.com
  $0 example.com

Notes:
  - If backup.wpress is not provided, the script will look for .wpress files
    in the script directory.
  - If multiple .wpress files are found, the script will ask you to choose one.
EOF
}

error_exit() {
    echo "Error: $1"
    exit 1
}

is_domain() {
    local domain="$1"
    [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]
}

is_wpress_arg() {
    local value="$1"

    [[ "$value" == *.wpress ]] || [ -f "$value" ] || [ -f "$SCRIPT_DIR/$value" ]
}

remove_last_domain_arg() {
    local last_index=$((${#DOMAINS[@]} - 1))
    unset "DOMAINS[$last_index]"
    DOMAINS=("${DOMAINS[@]}")
}

parse_args() {
    if [ "$#" -lt 1 ]; then
        usage
        exit 1
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -f|--file|--wpress)
                shift
                [ -n "$1" ] || error_exit "Missing .wpress file after --file"
                WPRESS_FILE="$1"
                ;;
            -g|--google-file-id|--file-id)
                shift
                [ -n "$1" ] || error_exit "Missing Google File ID after --google-file-id"
                GOOGLE_FILE_ID="$1"
                ;;
            --)
                shift
                while [ "$#" -gt 0 ]; do
                    DOMAINS+=("$1")
                    shift
                done
                break
                ;;
            -*)
                usage
                error_exit "Unknown option: $1"
                ;;
            *)
                DOMAINS+=("$1")
                ;;
        esac
        shift
    done

    if [ -n "$WPRESS_FILE" ] && [ -n "$GOOGLE_FILE_ID" ]; then
        error_exit "Use either --file or --google-file-id, not both"
    fi

    if [ -z "$WPRESS_FILE" ] && [ -z "$GOOGLE_FILE_ID" ] && [ "${#DOMAINS[@]}" -gt 1 ]; then
        local last_index=$((${#DOMAINS[@]} - 1))
        local last_arg="${DOMAINS[$last_index]}"

        if is_wpress_arg "$last_arg"; then
            WPRESS_FILE="$last_arg"
            remove_last_domain_arg
        elif ! is_domain "$last_arg"; then
            GOOGLE_FILE_ID="$last_arg"
            remove_last_domain_arg
        fi
    fi

    [ "${#DOMAINS[@]}" -gt 0 ] || error_exit "No domain provided"

    local domain
    for domain in "${DOMAINS[@]}"; do
        if ! is_domain "$domain"; then
            error_exit "Invalid domain: $domain"
        fi
    done
}

resolve_wpress_file() {
    local candidate="$1"

    if [ -f "$candidate" ]; then
        readlink -f "$candidate"
        return
    fi

    if [ -f "$SCRIPT_DIR/$candidate" ]; then
        readlink -f "$SCRIPT_DIR/$candidate"
        return
    fi

    return 1
}

choose_local_wpress_file() {
    local files=()
    mapfile -t files < <(find "$SCRIPT_DIR" -maxdepth 1 -name "*.wpress" -type f | sort)

    if [ "${#files[@]}" -eq 0 ]; then
        echo "Error: No .wpress file found in $SCRIPT_DIR"
        echo "Please place a .wpress backup file in the script directory or pass --file backup.wpress"
        exit 1
    fi

    if [ "${#files[@]}" -eq 1 ]; then
        BACKUP_SOURCE="${files[0]}"
        echo "Found local backup file: $(basename "$BACKUP_SOURCE")"
        return
    fi

    if [ ! -t 0 ]; then
        echo "Error: Multiple .wpress files found in $SCRIPT_DIR"
        echo "Please choose one explicitly with: $0 --file backup.wpress ${DOMAINS[*]}"
        exit 1
    fi

    echo "Multiple .wpress files found:"
    local index
    for index in "${!files[@]}"; do
        echo "  $((index + 1)). $(basename "${files[$index]}")"
    done

    local choice
    while true; do
        read -rp "Choose backup file [1-${#files[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#files[@]}" ]; then
            BACKUP_SOURCE="${files[$((choice - 1))]}"
            echo "Selected backup file: $(basename "$BACKUP_SOURCE")"
            return
        fi
        echo "Invalid choice. Please enter a number from 1 to ${#files[@]}."
    done
}

prepare_backup_source() {
    if [ -n "$GOOGLE_FILE_ID" ]; then
        echo "[Setup] Checking gdown installation..."
        if ! command -v gdown &> /dev/null; then
            echo "gdown not found. Installing gdown..."
            sudo apt-get update
            sudo apt-get install -y python3-pip
            pip3 install gdown
            export PATH="$HOME/.local/bin:$PATH"
        fi

        SOURCE_TEMP_DIR="/tmp/wp-restore-source-$$"
        mkdir -p "$SOURCE_TEMP_DIR" || error_exit "Failed to create temporary source directory"
        BACKUP_SOURCE="$SOURCE_TEMP_DIR/source.wpress"

        echo "[Setup] Downloading backup file from Google Drive..."
        gdown "https://drive.google.com/uc?id=${GOOGLE_FILE_ID}" -O "$BACKUP_SOURCE"

        [ -f "$BACKUP_SOURCE" ] || error_exit "Failed to download backup file"
        echo "Backup file downloaded successfully"
        return
    fi

    if [ -n "$WPRESS_FILE" ]; then
        BACKUP_SOURCE="$(resolve_wpress_file "$WPRESS_FILE")" || error_exit "Backup file not found: $WPRESS_FILE"

        if [[ "$BACKUP_SOURCE" != *.wpress ]]; then
            error_exit "Backup file must end with .wpress: $BACKUP_SOURCE"
        fi

        echo "Using local backup file: $(basename "$BACKUP_SOURCE")"
        return
    fi

    choose_local_wpress_file
}

fail_domain() {
    local domain="$1"
    local message="$2"
    local temp_dir="/tmp/wp-restore-${domain}"

    echo "Error: $message"
    rm -rf "$temp_dir"
    return 1
}

restore_domain() {
    local DOMAIN="$1"
    local BACKUP_FILE="${DOMAIN}.wpress"
    local TEMP_DIR="/tmp/wp-restore-${DOMAIN}"
    local WP_PATH="/var/www/$DOMAIN/htdocs"
    local UPLOAD_DIR="$WP_PATH/wp-content/ai1wm-backups"
    local OWNER_GROUP
    local EXT_DIR

    echo ""
    echo "=========================================="
    echo "Restoring domain: $DOMAIN"
    echo "=========================================="

    echo "[1/6] Preparing backup file..."
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR" || return 1
    cp "$BACKUP_SOURCE" "$TEMP_DIR/$BACKUP_FILE" || return 1
    echo "Backup prepared: $BACKUP_FILE"

    echo "[2/6] Checking if WordPress site exists..."
    if [ ! -d "$WP_PATH" ]; then
        fail_domain "$DOMAIN" "WordPress site not found at $WP_PATH"
        echo "Please create the site first using: sudo site $DOMAIN -wp"
        return 1
    fi

    if [ ! -f "/var/www/$DOMAIN/wp-config.php" ]; then
        fail_domain "$DOMAIN" "wp-config.php not found. Site may not be properly configured."
        return 1
    fi

    OWNER_GROUP="$(stat -c "%U:%G" "$WP_PATH")" || return 1
    echo "WordPress site found at $WP_PATH"

    echo "[3/6] Installing All-in-One WP Migration plugin..."
    cd "$WP_PATH" || return 1
    wp plugin delete --all --allow-root 2>/dev/null || true
    wp plugin install all-in-one-wp-migration --activate --allow-root

    if [ $? -ne 0 ]; then
        fail_domain "$DOMAIN" "Failed to install All-in-One WP Migration plugin"
        return 1
    fi

    sudo chown -R "$OWNER_GROUP" "$WP_PATH/wp-content/plugins/all-in-one-wp-migration/" || return 1
    sudo chmod -R 755 "$WP_PATH/wp-content/plugins/all-in-one-wp-migration/" || return 1

    echo "[4/6] Installing All-in-One WP Migration URL Extension..."
    if [ ! -f "$EXTENSION_ZIP" ]; then
        fail_domain "$DOMAIN" "Extension file not found at $EXTENSION_ZIP"
        echo "Please ensure all-in-one-wp-migration-url-extension.zip is in the script directory"
        return 1
    fi

    if wp plugin is-active all-in-one-wp-migration-url-extension --allow-root 2>/dev/null; then
        wp plugin deactivate all-in-one-wp-migration-url-extension --allow-root
    fi

    wp plugin delete all-in-one-wp-migration-url-extension --allow-root 2>/dev/null || true
    wp plugin install "$EXTENSION_ZIP" --activate --allow-root

    if [ $? -ne 0 ]; then
        fail_domain "$DOMAIN" "Failed to install URL Extension"
        return 1
    fi

    EXT_DIR="$WP_PATH/wp-content/plugins/all-in-one-wp-migration-url-extension/"
    sudo chown -R "$OWNER_GROUP" "$EXT_DIR" || return 1
    sudo chmod -R 755 "$EXT_DIR" || return 1

    echo "[5/6] Copying backup file..."
    sudo mkdir -p "$UPLOAD_DIR" || return 1
    sudo cp "$TEMP_DIR/$BACKUP_FILE" "$UPLOAD_DIR/" || return 1
    sudo chown -R www-data:www-data "$UPLOAD_DIR" || return 1
    sudo chmod 755 "$UPLOAD_DIR" || return 1
    echo "Backup file copied to: $UPLOAD_DIR/$BACKUP_FILE"

    echo "[6/6] Restoring WordPress backup..."
    cd "$WP_PATH" || return 1
    printf 'y\n' | wp ai1wm restore "$BACKUP_FILE" --allow-root

    if [ $? -ne 0 ]; then
        fail_domain "$DOMAIN" "Failed to restore backup"
        return 1
    fi

    echo "Restore completed successfully!"

    echo "Cleaning up backup file..."
    sudo rm -f "$UPLOAD_DIR/$BACKUP_FILE" || return 1

    echo "Setting proper permissions..."
    sudo chown -R www-data:www-data "$WP_PATH" || return 1
    sudo find "$WP_PATH" -type d -exec chmod 755 {} \; || return 1
    sudo find "$WP_PATH" -type f -exec chmod 644 {} \; || return 1

    echo "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"

    echo ""
    echo "WordPress site setup completed!"
    echo "Domain: $DOMAIN"
    echo "WordPress Admin: https://$DOMAIN/wp-admin"
    echo "Note: If SSL is not configured, use http:// instead of https://"

    return 0
}

cleanup_source_temp() {
    if [ -n "$SOURCE_TEMP_DIR" ] && [ -d "$SOURCE_TEMP_DIR" ]; then
        rm -rf "$SOURCE_TEMP_DIR"
    fi
}

trap cleanup_source_temp EXIT

parse_args "$@"

echo "=========================================="
echo "WordPress Site Clone Script"
echo "Domains: ${DOMAINS[*]}"
if [ -n "$GOOGLE_FILE_ID" ]; then
    echo "Mode: Google Drive backup"
    echo "Google File ID: $GOOGLE_FILE_ID"
else
    echo "Mode: Local .wpress backup"
fi
echo "=========================================="

prepare_backup_source

for domain in "${DOMAINS[@]}"; do
    if restore_domain "$domain"; then
        SUCCESS_DOMAINS+=("$domain")
    else
        FAILED_DOMAINS+=("$domain")
    fi
done

echo ""
echo "=========================================="
echo "Clone summary"
echo "Successful: ${#SUCCESS_DOMAINS[@]}"
if [ "${#SUCCESS_DOMAINS[@]}" -gt 0 ]; then
    echo "  ${SUCCESS_DOMAINS[*]}"
fi
echo "Failed: ${#FAILED_DOMAINS[@]}"
if [ "${#FAILED_DOMAINS[@]}" -gt 0 ]; then
    echo "  ${FAILED_DOMAINS[*]}"
fi
echo "=========================================="

if [ "${#FAILED_DOMAINS[@]}" -gt 0 ]; then
    exit 1
fi

exit 0
