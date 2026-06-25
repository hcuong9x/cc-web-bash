#!/bin/bash
# Restore one or more WordPress sites (Webinoly stack) from a .tgz backup archive.
# The same backup is applied to every domain in the same run.
#
# Usage:
#   ./restore-wp.sh --file backup.tgz domain1.com [domain2.com ...]
#   ./restore-wp.sh --gdrive-file-id FILE_ID domain1.com [domain2.com ...]
#
# Examples:
#   ./restore-wp.sh --file /root/wp-backups/example.com-20260625-120000.tgz example.com
#   ./restore-wp.sh --gdrive-file-id 1AbC2dEfG3h newsite.com
#   ./restore-wp.sh --file template.tgz --source-domain template.com site1.com site2.com

set -o pipefail

BACKUP_FILE=""
GDRIVE_FILE_ID=""
SOURCE_DOMAIN_OVERRIDE=""
USE_MAINTENANCE=0
KEEP_UPLOADS=0
DOMAINS=()
SUCCESS_DOMAINS=()
FAILED_DOMAINS=()
DOWNLOAD_TEMP=""

usage() {
    cat <<EOF
Usage:
  $0 --file backup.tgz domain1.com [domain2.com ...]
  $0 --gdrive-file-id FILE_ID domain1.com [domain2.com ...]

Backup source (one required):
  --file backup.tgz        path to local .tgz backup archive
  --gdrive-file-id ID      Google Drive file ID (gdown is auto-installed if missing)

Options:
  --source-domain DOMAIN   override source domain for URL search-replace
                           (default: read from backup metadata)
  --maintenance            enable maintenance mode during restore
  --keep-uploads           preserve current wp-content/uploads (not overwritten)
  -h, --help               show help

Prerequisites per domain:
  - Site must already exist: sudo site <domain> -wp
  - wp-config.php must be at /var/www/<domain>/wp-config.php

Notes:
  - One backup file is applied to all listed domains.
  - URLs are automatically updated from source domain to each target domain.
  - A failure on one domain does not stop the remaining domains.
EOF
}

error_exit() { echo "Error: $1" >&2; exit 1; }

is_domain() {
    [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]
}

parse_args() {
    if [ "$#" -lt 1 ]; then usage; exit 1; fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --file|-f)
                shift; [ -n "${1:-}" ] || error_exit "Missing value for --file"
                BACKUP_FILE="$1"
                ;;
            --gdrive-file-id|-g)
                shift; [ -n "${1:-}" ] || error_exit "Missing value for --gdrive-file-id"
                GDRIVE_FILE_ID="$1"
                ;;
            --source-domain)
                shift; [ -n "${1:-}" ] || error_exit "Missing value for --source-domain"
                SOURCE_DOMAIN_OVERRIDE="$1"
                ;;
            --maintenance)
                USE_MAINTENANCE=1
                ;;
            --keep-uploads)
                KEEP_UPLOADS=1
                ;;
            -h|--help)
                usage; exit 0
                ;;
            --)
                shift
                while [ "$#" -gt 0 ]; do DOMAINS+=("$1"); shift; done
                break
                ;;
            -*)
                error_exit "Unknown option: $1"
                ;;
            *)
                DOMAINS+=("$1")
                ;;
        esac
        shift
    done

    [ "${#DOMAINS[@]}" -gt 0 ] || error_exit "No domain provided"
    [ -n "$BACKUP_FILE" ] || [ -n "$GDRIVE_FILE_ID" ] || \
        error_exit "Provide --file or --gdrive-file-id"
    [ -z "$BACKUP_FILE" ] || [ -z "$GDRIVE_FILE_ID" ] || \
        error_exit "Use either --file or --gdrive-file-id, not both"

    local domain
    for domain in "${DOMAINS[@]}"; do
        is_domain "$domain" || error_exit "Invalid domain: $domain"
    done
}

ensure_gdown() {
    if ! command -v gdown &>/dev/null; then
        echo "gdown not found. Installing gdown..."
        sudo apt-get update -qq
        sudo apt-get install -y python3-pip
        pip3 install gdown
        export PATH="$HOME/.local/bin:$PATH"
    fi
}

download_from_gdrive() {
    echo "[Setup] Checking gdown installation..."
    ensure_gdown

    DOWNLOAD_TEMP="/tmp/wp-restore-source-$$"
    mkdir -p "$DOWNLOAD_TEMP" || error_exit "Failed to create download directory"
    local dest="$DOWNLOAD_TEMP/backup.tgz"

    echo "[Setup] Downloading backup from Google Drive..."
    gdown "https://drive.google.com/uc?id=${GDRIVE_FILE_ID}" -O "$dest"
    [ -f "$dest" ] || error_exit "Download failed — check the file ID and that sharing is set to 'Anyone with the link'"
    echo "Download complete: $dest"
    BACKUP_FILE="$dest"
}

cleanup_download() {
    [ -n "$DOWNLOAD_TEMP" ] && rm -rf "$DOWNLOAD_TEMP"
}

read_meta_value() {
    local file="$1"
    local key="$2"
    grep "^${key}=" "$file" 2>/dev/null | head -n1 | cut -d= -f2-
}

restore_domain() {
    local domain="$1"
    local wp_path="/var/www/$domain/htdocs"
    local wp_config="/var/www/$domain/wp-config.php"
    local tmp_dir="/tmp/wp-restore-${domain}-$$"

    echo ""
    echo "=========================================="
    echo "Restoring: $domain"
    echo "=========================================="

    echo "[1/6] Checking prerequisites..."
    if [ ! -d "$wp_path" ]; then
        echo "Error: WordPress site not found at $wp_path"
        echo "Create the site first: sudo site $domain -wp"
        return 1
    fi
    if [ ! -f "$wp_config" ]; then
        echo "Error: wp-config.php not found at $wp_config"
        return 1
    fi

    mkdir -p "$tmp_dir" || { echo "Error: Failed to create temp directory"; return 1; }

    echo "[2/6] Extracting and validating backup..."
    if ! tar -xzf "$BACKUP_FILE" -C "$tmp_dir" 2>/dev/null; then
        echo "Error: Failed to extract backup archive"
        rm -rf "$tmp_dir"
        return 1
    fi

    local required
    for required in files.tar.gz db.sql meta.env; do
        if [ ! -f "$tmp_dir/$required" ]; then
            echo "Error: Invalid backup — missing $required inside archive"
            rm -rf "$tmp_dir"
            return 1
        fi
    done

    local source_domain source_siteurl source_home
    source_domain="$(read_meta_value "$tmp_dir/meta.env" SOURCE_DOMAIN)"
    source_siteurl="$(read_meta_value "$tmp_dir/meta.env" SOURCE_SITEURL)"
    source_home="$(read_meta_value "$tmp_dir/meta.env" SOURCE_HOME)"
    local backup_created
    backup_created="$(read_meta_value "$tmp_dir/meta.env" BACKUP_CREATED_AT)"

    [ -n "$SOURCE_DOMAIN_OVERRIDE" ] && source_domain="$SOURCE_DOMAIN_OVERRIDE"

    echo "Backup created: ${backup_created:-unknown}"
    echo "Source domain:  ${source_domain:-unknown}"

    local target_url="https://$domain"

    if [ "$USE_MAINTENANCE" -eq 1 ]; then
        echo "Activating maintenance mode..."
        wp --allow-root --path="$wp_path" maintenance-mode activate 2>/dev/null || true
    fi

    echo "[3/6] Preparing docroot..."
    # Save uploads before wiping if requested
    if [ "$KEEP_UPLOADS" -eq 1 ] && [ -d "$wp_path/wp-content/uploads" ]; then
        echo "Saving current wp-content/uploads..."
        cp -rp "$wp_path/wp-content/uploads" "$tmp_dir/uploads_backup"
    fi

    # Guard against unsafe paths
    case "$wp_path" in
        /|/var|/var/www|/home)
            echo "Error: Refusing to wipe unsafe path: $wp_path"
            rm -rf "$tmp_dir"
            return 1
            ;;
    esac

    local owner_group
    owner_group="$(stat -c "%U:%G" "$wp_path")"
    find "$wp_path" -mindepth 1 -maxdepth 1 ! -name ".well-known" -exec rm -rf {} +

    echo "[4/6] Extracting WordPress files..."
    if ! tar -xzf "$tmp_dir/files.tar.gz" -C "$wp_path"; then
        echo "Error: Failed to extract WordPress files"
        rm -rf "$tmp_dir"
        return 1
    fi

    if [ "$KEEP_UPLOADS" -eq 1 ] && [ -d "$tmp_dir/uploads_backup" ]; then
        echo "Restoring saved uploads..."
        mkdir -p "$wp_path/wp-content/uploads"
        cp -rp "$tmp_dir/uploads_backup/." "$wp_path/wp-content/uploads/"
    fi

    echo "[5/6] Importing database..."
    if ! wp --allow-root --path="$wp_path" db reset --yes --quiet; then
        echo "Error: Database reset failed"
        rm -rf "$tmp_dir"
        return 1
    fi
    if ! wp --allow-root --path="$wp_path" db import "$tmp_dir/db.sql" --quiet; then
        echo "Error: Database import failed"
        rm -rf "$tmp_dir"
        return 1
    fi

    echo "[6/6] Updating URLs and fixing permissions..."
    if [ -n "$source_siteurl" ] && [ "$source_siteurl" != "$target_url" ]; then
        wp --allow-root --path="$wp_path" search-replace \
            "$source_siteurl" "$target_url" \
            --all-tables --precise --skip-columns=guid --quiet || true
    fi
    if [ -n "$source_home" ] && \
       [ "$source_home" != "$target_url" ] && \
       [ "$source_home" != "$source_siteurl" ]; then
        wp --allow-root --path="$wp_path" search-replace \
            "$source_home" "$target_url" \
            --all-tables --precise --skip-columns=guid --quiet || true
    fi
    if [ -n "$source_domain" ] && [ "$source_domain" != "$domain" ]; then
        wp --allow-root --path="$wp_path" search-replace \
            "$source_domain" "$domain" \
            --all-tables --precise --skip-columns=guid --quiet || true
    fi

    wp --allow-root --path="$wp_path" option update siteurl "$target_url" --quiet
    wp --allow-root --path="$wp_path" option update home "$target_url" --quiet

    chown -R "$owner_group" "$wp_path"
    find "$wp_path" -type d -exec chmod 755 {} +
    find "$wp_path" -type f -exec chmod 644 {} +

    wp --allow-root --path="$wp_path" cache flush >/dev/null 2>&1 || true

    if [ "$USE_MAINTENANCE" -eq 1 ]; then
        echo "Deactivating maintenance mode..."
        wp --allow-root --path="$wp_path" maintenance-mode deactivate 2>/dev/null || true
    fi

    rm -rf "$tmp_dir"
    echo "Restore complete: $target_url"
    return 0
}

# ── Main ──────────────────────────────────────────────────────────────────────

parse_args "$@"

command -v wp &>/dev/null || error_exit "WP-CLI (wp) is not installed"

if [ -n "$GDRIVE_FILE_ID" ]; then
    trap cleanup_download EXIT
    download_from_gdrive
else
    [ -f "$BACKUP_FILE" ] || error_exit "Backup file not found: $BACKUP_FILE"
    BACKUP_FILE="$(readlink -f "$BACKUP_FILE")"
fi

for domain in "${DOMAINS[@]}"; do
    if restore_domain "$domain"; then
        SUCCESS_DOMAINS+=("$domain")
    else
        FAILED_DOMAINS+=("$domain")
    fi
done

echo ""
echo "=========================================="
echo "RESTORE SUMMARY"
echo "=========================================="
echo "Total: ${#DOMAINS[@]} | Success: ${#SUCCESS_DOMAINS[@]} | Failed: ${#FAILED_DOMAINS[@]}"

if [ "${#SUCCESS_DOMAINS[@]}" -gt 0 ]; then
    echo "Success:"
    for d in "${SUCCESS_DOMAINS[@]}"; do echo "  ✓ $d"; done
fi

if [ "${#FAILED_DOMAINS[@]}" -gt 0 ]; then
    echo "Failed:"
    for d in "${FAILED_DOMAINS[@]}"; do echo "  ✗ $d"; done
    exit 1
fi

exit 0
