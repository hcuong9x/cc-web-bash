#!/bin/bash

set -euo pipefail

rand_alnum() { (set +o pipefail; LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"); }
die() { echo "[ERROR] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo $0 <domain>"
[[ $# -eq 1 ]]    || die "Usage: $0 <domain>"

DOMAIN="$1"
[[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9-]*\.)+[a-z]{2,}$ ]] || die "Invalid domain: $DOMAIN"

WP_ROOT="/var/www/$DOMAIN"
WP_HTDOCS="$WP_ROOT/htdocs"
WP_CONFIG="$WP_ROOT/wp-config.php"
WP_CONFIG_SAMPLE="$WP_HTDOCS/wp-config-sample.php"

[[ -d "$WP_HTDOCS" ]]        || die "Site not found: $WP_HTDOCS"
[[ -f "$WP_CONFIG_SAMPLE" ]] || die "wp-config-sample.php not found: $WP_CONFIG_SAMPLE"

DB_NAME="${DOMAIN//./_}"
DB_USER="$DB_NAME"
BACKUP=""

# ── backup ─────────────────────────────────────────────────────────────────────
if [[ -f "$WP_CONFIG" ]]; then
    BACKUP="${WP_CONFIG}.bak.$(date +%Y-%m-%d-%H%M%S)"
    cp "$WP_CONFIG" "$BACKUP"
    echo "[INFO] Backed up existing: $BACKUP"
fi

# ── generate password ──────────────────────────────────────────────────────────
DB_PASS="$(rand_alnum 24)"

# ── reset DB user password ─────────────────────────────────────────────────────
echo "[INFO] Resetting MariaDB password for '${DB_USER}'@'localhost' ..."
mysql -e "ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}'; FLUSH PRIVILEGES;" \
    || die "Failed to reset DB password. Ensure '${DB_USER}'@'localhost' exists in MariaDB."

# ── create wp-config.php from sample ──────────────────────────────────────────
cp "$WP_CONFIG_SAMPLE" "$WP_CONFIG"

# ── replace DB credentials ─────────────────────────────────────────────────────
sed -i "s|database_name_here|${DB_NAME}|" "$WP_CONFIG"
sed -i "s|username_here|${DB_USER}|"      "$WP_CONFIG"
sed -i "s|password_here|${DB_PASS}|"      "$WP_CONFIG"

# ── auth keys/salts ────────────────────────────────────────────────────────────
echo "[INFO] Fetching auth keys/salts ..."
SALTS="$(curl -s --max-time 5 'https://api.wordpress.org/secret-key/1.1/salt/' || true)"

if [[ -z "$SALTS" || ! "$SALTS" =~ "define" ]]; then
    echo "[WARN] WordPress salt API unreachable — generating locally"
    SALT_KEYS=(AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT)
    SALTS=""
    for key in "${SALT_KEYS[@]}"; do
        SALTS+="define( '${key}', '$(rand_alnum 64)' );"$'\n'
    done
    SALTS="${SALTS%$'\n'}"
fi

SALT_FILE="$(mktemp)"
printf '%s\n' "$SALTS" > "$SALT_FILE"

# Replace the 8 salt defines: keep everything before AUTH_KEY, insert new salts,
# skip old lines through NONCE_SALT.
awk -v saltfile="$SALT_FILE" '
    BEGIN { found=0; skip=0 }
    /define\(.*AUTH_KEY/ && !found {
        while ((getline line < saltfile) > 0) print line
        found=1; skip=1; next
    }
    skip && /define\(.*NONCE_SALT/ { skip=0; next }
    skip { next }
    { print }
' "$WP_CONFIG" > "${WP_CONFIG}.tmp" && mv "${WP_CONFIG}.tmp" "$WP_CONFIG"
rm -f "$SALT_FILE"

# ── permissions ────────────────────────────────────────────────────────────────
chown www-data:www-data "$WP_CONFIG"
chmod 644 "$WP_CONFIG"

# ── restart PHP-FPM ────────────────────────────────────────────────────────────
echo "[INFO] Restarting php8.4-fpm ..."
systemctl restart php8.4-fpm

# ── verify ─────────────────────────────────────────────────────────────────────
echo "[INFO] Verifying WordPress installation ..."
if wp --allow-root --path="$WP_HTDOCS" core is-installed 2>/dev/null; then
    WP_STATUS="OK"
else
    WP_STATUS="WARN — wp core check failed; verify site URL and DB are correct"
fi

echo ""
echo "========================================"
echo " wp-config.php REGENERATED"
echo "========================================"
echo "  Domain  : $DOMAIN"
echo "  DB_NAME : $DB_NAME"
echo "  DB_USER : $DB_USER"
echo "  DB_PASS : $DB_PASS  <-- save this!"
[[ -n "$BACKUP" ]] && echo "  Backup  : $BACKUP"
echo "  Status  : $WP_STATUS"
echo "========================================"
