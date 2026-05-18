#!/bin/bash

# Delete .zip files from WordPress plugin folders:
#   /var/www/*/htdocs/wp-content/plugins

set -o pipefail

BASE_DIR="/var/www"
DRY_RUN=0
FORCE=0
RECURSIVE=0

usage() {
    cat <<EOF
Usage:
  $0 [--dry-run] [--force] [--recursive]

Options:
  --dry-run, -n     Show zip files only, do not delete
  --force, -y       Delete without confirmation
  --recursive, -r   Also delete zip files inside plugin subfolders
  --help, -h        Show this help

Examples:
  $0 --dry-run
  $0 --force
  $0 --recursive --force
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -n|--dry-run)
            DRY_RUN=1
            ;;
        -y|--force)
            FORCE=1
            ;;
        -r|--recursive)
            RECURSIVE=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

PLUGIN_DIRS=()
ZIP_FILES=()

shopt -s nullglob
for plugin_dir in "$BASE_DIR"/*/htdocs/wp-content/plugins; do
    [ -d "$plugin_dir" ] || continue
    PLUGIN_DIRS+=("$plugin_dir")
done
shopt -u nullglob

if [ "${#PLUGIN_DIRS[@]}" -eq 0 ]; then
    echo "No plugin folders found at: $BASE_DIR/*/htdocs/wp-content/plugins"
    exit 0
fi

for plugin_dir in "${PLUGIN_DIRS[@]}"; do
    if [ "$RECURSIVE" -eq 1 ]; then
        while IFS= read -r -d '' zip_file; do
            ZIP_FILES+=("$zip_file")
        done < <(find "$plugin_dir" -type f -name "*.zip" -print0)
    else
        while IFS= read -r -d '' zip_file; do
            ZIP_FILES+=("$zip_file")
        done < <(find "$plugin_dir" -maxdepth 1 -type f -name "*.zip" -print0)
    fi
done

if [ "${#ZIP_FILES[@]}" -eq 0 ]; then
    echo "No zip files found."
    exit 0
fi

echo "Found ${#ZIP_FILES[@]} zip file(s):"
for zip_file in "${ZIP_FILES[@]}"; do
    echo "  $zip_file"
done

if [ "$DRY_RUN" -eq 1 ]; then
    echo ""
    echo "Dry run only. No files deleted."
    exit 0
fi

if [ "$FORCE" -ne 1 ]; then
    if [ ! -t 0 ]; then
        echo ""
        echo "Error: Confirmation required. Re-run with --force to delete in non-interactive mode."
        exit 1
    fi

    echo ""
    read -rp "Delete these zip files? [y/N]: " confirm
    case "$confirm" in
        y|Y|yes|YES)
            ;;
        *)
            echo "Cancelled."
            exit 0
            ;;
    esac
fi

deleted_count=0
failed_count=0

for zip_file in "${ZIP_FILES[@]}"; do
    if rm -f -- "$zip_file"; then
        deleted_count=$((deleted_count + 1))
        echo "Deleted: $zip_file"
    else
        failed_count=$((failed_count + 1))
        echo "Failed: $zip_file"
    fi
done

echo ""
echo "Done."
echo "Deleted: $deleted_count"
echo "Failed: $failed_count"

if [ "$failed_count" -gt 0 ]; then
    exit 1
fi

exit 0
