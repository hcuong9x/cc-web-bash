#!/usr/bin/env bash
set -euo pipefail

detect_php_fpm_version() {
  local ver=""

  if systemctl list-units --type=service --all 2>/dev/null | grep -q 'php8\.4-fpm\.service'; then
    ver="8.4"
  elif systemctl list-units --type=service --all 2>/dev/null | grep -q 'php8\.3-fpm\.service'; then
    ver="8.3"
  else
    ver="$(find /etc/php -maxdepth 1 -mindepth 1 -type d 2>/dev/null \
      | sed 's#.*/##' \
      | grep -E '^[0-9]+\.[0-9]+$' \
      | sort -Vr \
      | while read -r v; do
          if [ -f "/etc/php/$v/fpm/php.ini" ] && [ -f "/etc/php/$v/fpm/pool.d/www.conf" ]; then
            echo "$v"
            break
          fi
        done)"
  fi

  if [ -z "$ver" ]; then
    echo "[ERROR] Khong tim thay PHP-FPM version phu hop trong /etc/php" >&2
    exit 1
  fi

  echo "$ver"
}

backup_file() {
  local file="$1"
  cp "$file" "${file}.bak.$(date +%F-%H%M%S)"
}

set_ini_value() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -qE "^[;[:space:]]*${key}[[:space:]]*=" "$file"; then
    sed -i -E "s|^[;[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
  else
    echo "${key} = ${value}" >> "$file"
  fi
}

ensure_fpm_pool_value() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -qE "^[;[:space:]]*${key}[[:space:]]*=" "$file"; then
    sed -i -E "s|^[;[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
  else
    echo "${key} = ${value}" >> "$file"
  fi
}

PHP_VER="${PHP_VER:-$(detect_php_fpm_version)}"
PHP_INI="/etc/php/${PHP_VER}/fpm/php.ini"
FPM_WWW="/etc/php/${PHP_VER}/fpm/pool.d/www.conf"
FPM_BIN="php-fpm${PHP_VER}"
FPM_SERVICE="php${PHP_VER}-fpm"

if [ ! -f "$PHP_INI" ]; then
  echo "[ERROR] Khong tim thay file: $PHP_INI" >&2
  exit 1
fi

if [ ! -f "$FPM_WWW" ]; then
  echo "[ERROR] Khong tim thay file: $FPM_WWW" >&2
  exit 1
fi

echo "[INFO] PHP-FPM version: ${PHP_VER}"
echo "[INFO] php.ini: ${PHP_INI}"
echo "[INFO] pool config: ${FPM_WWW}"
echo

echo "[1/6] Backup config files..."
backup_file "$PHP_INI"
backup_file "$FPM_WWW"

echo "[2/6] Update PHP-FPM php.ini..."
set_ini_value "$PHP_INI" "memory_limit" "512M"
set_ini_value "$PHP_INI" "max_execution_time" "300"
set_ini_value "$PHP_INI" "max_input_time" "300"
set_ini_value "$PHP_INI" "max_input_vars" "10000"
set_ini_value "$PHP_INI" "post_max_size" "128M"
set_ini_value "$PHP_INI" "upload_max_filesize" "128M"

echo "[3/6] Update PHP-FPM pool config..."
ensure_fpm_pool_value "$FPM_WWW" "request_terminate_timeout" "300"
ensure_fpm_pool_value "$FPM_WWW" "request_slowlog_timeout" "5s"
ensure_fpm_pool_value "$FPM_WWW" "slowlog" "/var/log/php${PHP_VER}-fpm-slow.log"
ensure_fpm_pool_value "$FPM_WWW" "pm" "dynamic"
ensure_fpm_pool_value "$FPM_WWW" "pm.max_children" "4"
ensure_fpm_pool_value "$FPM_WWW" "pm.start_servers" "2"
ensure_fpm_pool_value "$FPM_WWW" "pm.min_spare_servers" "1"
ensure_fpm_pool_value "$FPM_WWW" "pm.max_spare_servers" "3"
ensure_fpm_pool_value "$FPM_WWW" "pm.max_requests" "300"

echo "[4/6] Validate PHP-FPM config..."
if command -v "$FPM_BIN" >/dev/null 2>&1; then
  "$FPM_BIN" -t
else
  echo "[WARN] Khong tim thay binary $FPM_BIN, bo qua test bang binary."
fi

echo "[5/6] Restart services..."
systemctl restart "$FPM_SERVICE"
systemctl restart nginx

echo "[6/6] Show final values..."
echo
echo "=== php.ini (${PHP_VER}) ==="
egrep "memory_limit|max_execution_time|max_input_time|max_input_vars|post_max_size|upload_max_filesize" "$PHP_INI" || true
echo
echo "=== www.conf (${PHP_VER}) ==="
egrep "request_terminate_timeout|request_slowlog_timeout|slowlog|^pm[.]|^pm =" "$FPM_WWW" || true

echo
echo "[OK] Done."
echo "[INFO] Xem log neu van loi:"
echo "tail -f /var/log/nginx/error.log"
echo "tail -f /var/log/php${PHP_VER}-fpm-slow.log"
echo "journalctl -u ${FPM_SERVICE} -f"
