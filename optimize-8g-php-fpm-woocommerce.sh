#!/bin/bash
# =============================================
# Optimize Webinoly Server 8GB RAM - WooCommerce 2026
# PHP 8.4 + Nginx + MariaDB
# =============================================

set -e

PHP_VER="8.4"
PHP_POOL="/etc/php/${PHP_VER}/fpm/pool.d/www.conf"
PHP_INI="/etc/php/${PHP_VER}/fpm/php.ini"
OPCACHE_INI="/etc/php/${PHP_VER}/mods-available/opcache.ini"
MYSQL_CNF="/etc/mysql/mariadb.conf.d/99-webinoly-8gb.cnf"
NGINX_CNF="/etc/nginx/nginx.conf"
NGINX_FASTCGI_TUNING="/etc/nginx/conf.d/99-php-fcgi-timeouts.conf"
NGINX_FASTCGI_CNF="/etc/nginx/conf.d/fastcgi.conf"
PHP_FPM_SLOWLOG="/var/log/php${PHP_VER}-fpm-slow.log"
SYSCTL_CNF="/etc/sysctl.d/99-webinoly-8gb.conf"

set_ini_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local key_re

  key_re=$(printf '%s' "$key" | sed -e 's/[][\\/.*^$(){}?+|]/\\&/g')
  if grep -Eq "^[;[:space:]]*${key_re}[[:space:]]*=" "$file"; then
    sed -i -E "s|^[;[:space:]]*${key_re}[[:space:]]*=.*|${key} = ${value}|" "$file"
  else
    echo "${key} = ${value}" >> "$file"
  fi
}

ensure_single_nginx_directive() {
  local file="$1"
  local key="$2"
  local value="$3"
  local key_re

  key_re=$(printf '%s' "$key" | sed -e 's/[][\\/.*^$(){}?+|]/\\&/g')
  sed -i -E "/^[[:space:]]*${key_re}[[:space:]]+[^;]*;/d" "$file"
  echo "${key} ${value};" >> "$file"
}

ensure_nginx_http_directive() {
  local file="$1"
  local key="$2"
  local value="$3"
  local key_re

  key_re=$(printf '%s' "$key" | sed -e 's/[][\\/.*^$(){}?+|]/\\&/g')
  sed -i -E "/^[[:space:]]*${key_re}[[:space:]]+[^;]*;/d" "$file"
  sed -i "/^[[:space:]]*http[[:space:]]*{/a \    ${key} ${value};" "$file"
}

echo "=== Starting Optimization for 8GB RAM Server ==="

# Backup configs
echo "== Backup configs =="
DATE=$(date +%F-%H%M%S)
cp "$PHP_POOL" "${PHP_POOL}.bak.$DATE"
cp "$PHP_INI" "${PHP_INI}.bak.$DATE"
cp "$OPCACHE_INI" "${OPCACHE_INI}.bak.$DATE"
cp "$NGINX_CNF" "${NGINX_CNF}.bak.$DATE"
[ -f "$MYSQL_CNF" ] && cp "$MYSQL_CNF" "${MYSQL_CNF}.bak.$DATE"
[ -f "$NGINX_FASTCGI_TUNING" ] && cp "$NGINX_FASTCGI_TUNING" "${NGINX_FASTCGI_TUNING}.bak.$DATE"
[ -f "$NGINX_FASTCGI_CNF" ] && cp "$NGINX_FASTCGI_CNF" "${NGINX_FASTCGI_CNF}.bak.$DATE"
echo "Backup completed."

# ====================== PHP-FPM ======================
echo "== Optimize PHP-FPM (dynamic) =="
set_ini_value "$PHP_POOL" "pm" "dynamic"
set_ini_value "$PHP_POOL" "pm.max_children" "38"
set_ini_value "$PHP_POOL" "pm.start_servers" "10"
set_ini_value "$PHP_POOL" "pm.min_spare_servers" "7"
set_ini_value "$PHP_POOL" "pm.max_spare_servers" "20"
set_ini_value "$PHP_POOL" "pm.max_requests" "500"
set_ini_value "$PHP_POOL" "request_terminate_timeout" "600"
set_ini_value "$PHP_POOL" "listen.backlog" "8192"
set_ini_value "$PHP_POOL" "request_slowlog_timeout" "15s"
set_ini_value "$PHP_POOL" "slowlog" "$PHP_FPM_SLOWLOG"

# ====================== php.ini ======================
echo "== Optimize php.ini =="
set_ini_value "$PHP_INI" "memory_limit" "768M"
set_ini_value "$PHP_INI" "max_execution_time" "600"
set_ini_value "$PHP_INI" "max_input_time" "600"
set_ini_value "$PHP_INI" "max_input_vars" "15000"
set_ini_value "$PHP_INI" "post_max_size" "512M"
set_ini_value "$PHP_INI" "upload_max_filesize" "512M"
set_ini_value "$PHP_INI" "realpath_cache_size" "8192K"
set_ini_value "$PHP_INI" "realpath_cache_ttl" "600"
set_ini_value "$PHP_INI" "opcache.enable" "1"

# ====================== OPcache ======================
echo "== Optimize OPcache (PHP 8.4) =="
cat > "$OPCACHE_INI" <<'EOF'
zend_extension=opcache.so
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=384
opcache.interned_strings_buffer=48
opcache.max_accelerated_files=100000
opcache.revalidate_freq=0
opcache.validate_timestamps=0
opcache.save_comments=1
; JIT - Tracing for PHP 8.4
opcache.jit=tracing
opcache.jit_buffer_size=128M
EOF

# ====================== MariaDB ======================
echo "== Optimize MariaDB (2.5G Buffer Pool, 220 connections) =="
cat > "$MYSQL_CNF" <<'EOF'
[mysqld]
# InnoDB Main Settings
innodb_buffer_pool_size         = 2560M
innodb_buffer_pool_instances    = 4
innodb_log_file_size            = 768M
innodb_log_buffer_size          = 64M
innodb_flush_log_at_trx_commit  = 2
innodb_flush_method             = O_DIRECT
innodb_file_per_table           = 1

# Connection & Thread
max_connections                 = 220
thread_cache_size               = 120
table_open_cache                = 5000
table_definition_cache          = 3000
open_files_limit                = 65535
back_log                        = 220
max_connect_errors              = 100000
wait_timeout                    = 60
interactive_timeout             = 120

# Temporary tables
tmp_table_size                  = 96M
max_heap_table_size             = 96M

# Per-connection buffers kept conservative for 220 max connections.
sort_buffer_size                = 1M
join_buffer_size                = 1M
read_buffer_size                = 512K
read_rnd_buffer_size            = 1M

# Slow Query Log
slow_query_log                  = 1
slow_query_log_file             = /var/log/mysql/slow.log
long_query_time                 = 2

# Other
max_allowed_packet              = 256M
EOF

# ====================== Nginx ======================
echo "== Optimize Nginx =="
sed -i -E \
  -e 's/^[[:space:]]*worker_processes[[:space:]]+[^;]+;/worker_processes auto;/' \
  -e '/^[[:space:]]*worker_rlimit_nofile[[:space:]]+[0-9]+;/d' \
  "$NGINX_CNF"
sed -i '/^[[:space:]]*worker_processes[[:space:]]\+/a worker_rlimit_nofile 65535;' "$NGINX_CNF"

# Basic tuning for WooCommerce imports, bulk edits, and many vhosts.
ensure_nginx_http_directive "$NGINX_CNF" "client_max_body_size" "512M"
ensure_nginx_http_directive "$NGINX_CNF" "server_names_hash_bucket_size" "512"
ensure_nginx_http_directive "$NGINX_CNF" "server_names_hash_max_size" "2048"

if [ -f "$NGINX_FASTCGI_CNF" ]; then
  # Webinoly usually defines fastcgi_* directives here. Ensure single values to avoid duplicate errors.
  ensure_single_nginx_directive "$NGINX_FASTCGI_CNF" "fastcgi_connect_timeout" "60s"
  ensure_single_nginx_directive "$NGINX_FASTCGI_CNF" "fastcgi_send_timeout" "600s"
  ensure_single_nginx_directive "$NGINX_FASTCGI_CNF" "fastcgi_read_timeout" "600s"
  ensure_single_nginx_directive "$NGINX_FASTCGI_CNF" "fastcgi_buffers" "8 256k"
  ensure_single_nginx_directive "$NGINX_FASTCGI_CNF" "fastcgi_buffer_size" "256k"
  ensure_single_nginx_directive "$NGINX_FASTCGI_CNF" "fastcgi_busy_buffers_size" "512k"
  [ -f "$NGINX_FASTCGI_TUNING" ] && rm -f "$NGINX_FASTCGI_TUNING"
else
  cat > "$NGINX_FASTCGI_TUNING" <<'EOF'
# Bulk edit and long admin requests in WooCommerce can exceed nginx 60s defaults.
fastcgi_connect_timeout 60s;
fastcgi_send_timeout 600s;
fastcgi_read_timeout 600s;
fastcgi_buffers 8 256k;
fastcgi_buffer_size 256k;
fastcgi_busy_buffers_size 512k;
EOF
fi

# ====================== System Limits ======================
echo "== System Limits =="
cat > /etc/security/limits.d/99-webinoly.conf <<'EOF'
www-data soft nofile 65535
www-data hard nofile 65535
mysql    soft nofile 65535
mysql    hard nofile 65535
EOF

mkdir -p /etc/systemd/system/php${PHP_VER}-fpm.service.d
cat > /etc/systemd/system/php${PHP_VER}-fpm.service.d/override.conf <<EOF
[Service]
LimitNOFILE=65535
EOF

mkdir -p /etc/systemd/system/nginx.service.d
cat > /etc/systemd/system/nginx.service.d/limits.conf <<'EOF'
[Service]
LimitNOFILE=65535
EOF

mkdir -p /etc/systemd/system/mariadb.service.d
cat > /etc/systemd/system/mariadb.service.d/limits.conf <<'EOF'
[Service]
LimitNOFILE=65535
EOF

# ====================== Sysctl ======================
echo "== Sysctl Optimization =="
cat > "$SYSCTL_CNF" <<'EOF'
vm.swappiness = 10
vm.vfs_cache_pressure = 50
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 16384
net.core.netdev_max_backlog = 8192
EOF

# Apply only this tuning file to avoid noisy warnings from unrelated sysctl fragments.
sysctl -p "$SYSCTL_CNF" >/dev/null

# ====================== Test & Restart ======================
echo "== Testing configurations =="
if php-fpm${PHP_VER} -t; then
  echo "PHP-FPM config: OK"
else
  echo "PHP-FPM config: FAILED"
  exit 1
fi

if nginx -t; then
  echo "Nginx config: OK"
else
  echo "Nginx config: FAILED"
  exit 1
fi

echo "== Restarting services =="
systemctl daemon-reload
systemctl restart php${PHP_VER}-fpm
systemctl restart nginx
systemctl restart mariadb

# ====================== Journal Log Cleanup ======================
echo "== Cleaning systemd journal logs =="
if command -v journalctl >/dev/null 2>&1; then
  journalctl --vacuum-size=500M --vacuum-time=14d || true
fi

echo "========================================"
echo "DONE! Optimization for 8GB RAM applied."
echo "Khuyen nghi: Theo doi RAM & load trong 24-48h dau."
echo "Dung lenh: htop, free -h, mysqladmin status"
echo "========================================"
