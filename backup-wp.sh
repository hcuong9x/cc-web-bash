#!/bin/bash
# Backup one or more WordPress sites (Webinoly stack) to .tgz archives,
# optionally uploading to Google Drive via rclone.
#
# Usage:
#   ./backup-wp.sh [options] domain1.com [domain2.com ...]
#
# Examples:
#   ./backup-wp.sh example.com
#   ./backup-wp.sh --gdrive-folder-id 1AbC2dEfG3h example.com shop.com
#   ./backup-wp.sh --exclude-uploads --output-dir /mnt/backup site.com

set -o pipefail

OUTPUT_DIR="/root/wp-backups"
GDRIVE_FOLDER_ID=""
RCLONE_REMOTE="gdrive"
EXCLUDE_UPLOADS=0
DB_ONLY=0
ALL_SITES=0
DOMAINS=()
SUCCESS_DOMAINS=()
FAILED_DOMAINS=()

usage() {
    cat <<EOF
Usage:
  $0 [options] domain1.com [domain2.com ...]

Options:
  --all                    auto-discover and backup all WordPress sites in /var/www
  --output-dir DIR         local directory to save backups (default: /root/wp-backups)
  --gdrive-folder-id ID    upload to this Google Drive folder ID
  --rclone-remote NAME     rclone remote name (default: gdrive)
  --exclude-uploads        exclude wp-content/uploads (lighter backup, loses media)
  --db-only                backup database only (no files) — fastest, smallest
  -h, --help               show help

Note: maintenance mode is always enabled during backup to prevent file corruption.

Archive format:
  Each domain produces: <domain>-YYYYMMDD-HHMMSS-<type>.tgz
  Types: full (default), noup (--exclude-uploads), db (--db-only)
    ├── files.tar.gz   WordPress docroot (excluding cache, ai1wm-backups)
    ├── db.sql         Full database dump
    └── meta.env       Source domain, URLs, table prefix, timestamp

Google Drive upload:
  Requires rclone with a configured remote. One-time setup:
    curl https://rclone.org/install.sh | sudo bash
    rclone config   # create a remote named 'gdrive' pointing to Google Drive
EOF
}

error_exit() { echo "Error: $1" >&2; exit 1; }

is_domain() {
    [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]
}

discover_all_sites() {
    local dir domain
    for dir in /var/www/*/; do
        domain="${dir%/}"
        domain="${domain##*/}"
        # skip system/non-domain directories
        [[ "$domain" =~ ^(html|default|phpmyadmin|_)$ ]] && continue
        [ -f "/var/www/$domain/wp-config.php" ] || continue
        [ -d "/var/www/$domain/htdocs" ] || continue
        DOMAINS+=("$domain")
    done
    if [ "${#DOMAINS[@]}" -eq 0 ]; then
        error_exit "No WordPress sites found in /var/www"
    fi
    echo "Auto-discovered ${#DOMAINS[@]} site(s): ${DOMAINS[*]}"
}

parse_args() {
    if [ "$#" -lt 1 ]; then usage; exit 1; fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --all)
                ALL_SITES=1
                ;;
            --output-dir)
                shift; [ -n "${1:-}" ] || error_exit "Missing value for --output-dir"
                OUTPUT_DIR="$1"
                ;;
            --gdrive-folder-id)
                shift; [ -n "${1:-}" ] || error_exit "Missing value for --gdrive-folder-id"
                GDRIVE_FOLDER_ID="$1"
                ;;
            --rclone-remote)
                shift; [ -n "${1:-}" ] || error_exit "Missing value for --rclone-remote"
                RCLONE_REMOTE="$1"
                ;;
            --exclude-uploads)
                EXCLUDE_UPLOADS=1
                ;;
            --db-only)
                DB_ONLY=1
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

    if [ "$ALL_SITES" -eq 1 ]; then
        [ "${#DOMAINS[@]}" -eq 0 ] || error_exit "--all cannot be combined with explicit domains"
        return
    fi

    [ "${#DOMAINS[@]}" -gt 0 ] || error_exit "No domain provided. Use --all to backup all sites."

    local domain
    for domain in "${DOMAINS[@]}"; do
        is_domain "$domain" || error_exit "Invalid domain: $domain"
    done
}

ensure_rclone() {
    if ! command -v rclone &>/dev/null; then
        echo ""
        echo "rclone is not installed. Install it with:"
        echo "  curl https://rclone.org/install.sh | sudo bash"
        echo ""
        echo "Then configure Google Drive (one-time):"
        echo "  rclone config"
        echo "  -> Create a new remote named '${RCLONE_REMOTE}' -> Google Drive"
        error_exit "rclone is required for Google Drive upload"
    fi

    if ! rclone listremotes 2>/dev/null | grep -q "^${RCLONE_REMOTE}:$"; then
        echo ""
        echo "rclone remote '${RCLONE_REMOTE}' is not configured."
        echo "Run: rclone config"
        echo "Create a new remote named '${RCLONE_REMOTE}' pointing to Google Drive."
        error_exit "rclone remote '${RCLONE_REMOTE}' not found"
    fi
}

backup_domain() {
    local domain="$1"
    local wp_path="/var/www/$domain/htdocs"
    local wp_config="/var/www/$domain/wp-config.php"
    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"
    local backup_type
    if [ "$DB_ONLY" -eq 1 ]; then
        backup_type="db"
    elif [ "$EXCLUDE_UPLOADS" -eq 1 ]; then
        backup_type="noup"
    else
        backup_type="full"
    fi
    local base_name="${domain}-${timestamp}-${backup_type}"
    local tmp_dir="/tmp/wp-backup-${domain}-$$"

    echo ""
    echo "=========================================="
    echo "Backing up: $domain"
    echo "=========================================="

    echo "[1/5] Checking prerequisites..."
    if [ ! -d "$wp_path" ]; then
        echo "Error: WordPress site not found at $wp_path"
        return 1
    fi
    if [ ! -f "$wp_config" ]; then
        echo "Error: wp-config.php not found at $wp_config"
        return 1
    fi

    mkdir -p "$tmp_dir" || { echo "Error: Failed to create temp directory"; return 1; }

    deactivate_maintenance() {
        wp --allow-root --path="$wp_path" maintenance-mode deactivate 2>/dev/null || true
    }

    echo "Activating maintenance mode..."
    wp --allow-root --path="$wp_path" maintenance-mode activate 2>/dev/null || true

    echo "[2/5] Exporting database..."
    if ! wp --allow-root --path="$wp_path" db export "$tmp_dir/db.sql" --add-drop-table --quiet; then
        echo "Error: Database export failed"
        deactivate_maintenance
        rm -rf "$tmp_dir"
        return 1
    fi

    if [ "$DB_ONLY" -eq 1 ]; then
        echo "[3/5] Skipping file archive (db-only backup)..."
    else
        echo "[3/5] Archiving WordPress files..."
        local tar_excludes=(
            "--exclude=./wp-content/cache"
            "--exclude=./wp-content/ai1wm-backups"
        )
        if [ "$EXCLUDE_UPLOADS" -eq 1 ]; then
            tar_excludes+=("--exclude=./wp-content/uploads")
            echo "Note: Excluding wp-content/uploads"
        fi
        if ! tar -C "$wp_path" "${tar_excludes[@]}" -czf "$tmp_dir/files.tar.gz" .; then
            echo "Error: File archive failed"
            deactivate_maintenance
            rm -rf "$tmp_dir"
            return 1
        fi
    fi

    echo "[4/5] Writing backup metadata..."
    local siteurl home table_prefix
    siteurl="$(wp --allow-root --path="$wp_path" option get siteurl --quiet 2>/dev/null || true)"
    home="$(wp --allow-root --path="$wp_path" option get home --quiet 2>/dev/null || true)"
    table_prefix="$(wp --allow-root --path="$wp_path" config get table_prefix --quiet 2>/dev/null || true)"

    cat > "$tmp_dir/meta.env" <<METAEOF
SOURCE_DOMAIN=$domain
SOURCE_WP_PATH=$wp_path
SOURCE_SITEURL=$siteurl
SOURCE_HOME=$home
SOURCE_TABLE_PREFIX=$table_prefix
BACKUP_CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
METAEOF

    echo "Deactivating maintenance mode..."
    deactivate_maintenance

    echo "[5/5] Packing archive..."
    local archive_path="$OUTPUT_DIR/$base_name.tgz"
    local sha_path="$OUTPUT_DIR/$base_name.sha256"

    mkdir -p "$OUTPUT_DIR"
    local pack_files=(db.sql meta.env)
    [ "$DB_ONLY" -eq 0 ] && pack_files=(db.sql files.tar.gz meta.env)
    if ! tar -C "$tmp_dir" -czf "$archive_path" "${pack_files[@]}"; then
        echo "Error: Final archive packing failed"
        rm -rf "$tmp_dir"
        return 1
    fi

    local sha_value
    sha_value="$(sha256sum "$archive_path" | awk '{print $1}')"
    printf '%s  %s\n' "$sha_value" "$base_name.tgz" > "$sha_path"
    rm -rf "$tmp_dir"

    local size
    size="$(du -sh "$archive_path" 2>/dev/null | awk '{print $1}')"
    echo "Backup saved: $archive_path ($size)"
    echo "SHA256: $sha_value"

    if [ -n "$GDRIVE_FOLDER_ID" ]; then
        local ym
        ym="$(date +%Y-%m)"
        local gdrive_path="${domain}/${ym}"
        echo "Uploading to Google Drive (${gdrive_path}/)..."
        if rclone copy "$archive_path" "${RCLONE_REMOTE}:${gdrive_path}/" \
                --drive-root-folder-id "$GDRIVE_FOLDER_ID" \
                --progress; then
            rclone copy "$sha_path" "${RCLONE_REMOTE}:${gdrive_path}/" \
                --drive-root-folder-id "$GDRIVE_FOLDER_ID" 2>/dev/null || true
            echo "Uploaded: $base_name.tgz"
            echo "Restore command:"
            echo "  ./restore-wp.sh --gdrive-folder-id $GDRIVE_FOLDER_ID --gdrive-path ${gdrive_path}/$base_name.tgz $domain"
        else
            echo "Warning: Google Drive upload failed for $domain"
            return 1
        fi
    fi

    return 0
}

# ── Main ──────────────────────────────────────────────────────────────────────

parse_args "$@"

command -v wp &>/dev/null || error_exit "WP-CLI (wp) is not installed"

if [ "$ALL_SITES" -eq 1 ]; then
    discover_all_sites
fi

if [ -n "$GDRIVE_FOLDER_ID" ]; then
    ensure_rclone
fi

mkdir -p "$OUTPUT_DIR"

for domain in "${DOMAINS[@]}"; do
    if backup_domain "$domain"; then
        SUCCESS_DOMAINS+=("$domain")
    else
        FAILED_DOMAINS+=("$domain")
    fi
done

echo ""
echo "=========================================="
echo "BACKUP SUMMARY"
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
