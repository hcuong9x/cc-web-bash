#!/bin/bash

set -euo pipefail

rand_alnum() { (set +o pipefail; LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"); }

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <domain1> [domain2 ...]"
  exit 1
fi

ADMIN_EMAIL="heworld39@gmail.com"
SUMMARY=()
FAILED=()

for DOMAIN in "$@"; do
  echo ""
  echo "=== [$DOMAIN] ==="

  WP_PATH="/var/www/$DOMAIN/htdocs"
  ADMIN_PASS="$(rand_alnum 16)"
  SITE_TITLE="${DOMAIN%%.*}"

  # 1. Create site — Webinoly handles nginx, PHP-FPM, DB, and wp-config.php
  if ! site "$DOMAIN" -wp; then
    echo "[ERROR] site creation failed: $DOMAIN"
    FAILED+=("$DOMAIN")
    continue
  fi

  # 2. Install WordPress non-interactively (no prompts, no email)
  if ! wp core install \
      --url="https://$DOMAIN" \
      --title="$SITE_TITLE" \
      --admin_user="admin" \
      --admin_password="$ADMIN_PASS" \
      --admin_email="$ADMIN_EMAIL" \
      --skip-email \
      --path="$WP_PATH" \
      --allow-root; then
    echo "[ERROR] wp core install failed: $DOMAIN"
    FAILED+=("$DOMAIN")
    continue
  fi

  # 3. Disable WP-Admin HTTP auth + enable SSL
  sudo httpauth "$DOMAIN" -wp-admin=off
  sudo site "$DOMAIN" -ssl=on

  SUMMARY+=("$DOMAIN | admin / $ADMIN_PASS")
  echo "[$DOMAIN] Done."
done

echo ""
echo "========================================"
echo " CREDENTIALS SUMMARY"
echo "========================================"
for LINE in "${SUMMARY[@]+"${SUMMARY[@]}"}"; do
  echo "  $LINE"
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo ""
  echo "FAILED domains:"
  for D in "${FAILED[@]}"; do
    echo "  - $D"
  done
  exit 1
fi
