#!/bin/bash
# =============================================
# Optimize Webinoly Server 3GB RAM - Cân bằng 2026
# PHP 8.4 + Nginx + MariaDB + WooCommerce
# =============================================

set -e

PHP_VER="8.4"
PHP_POOL="/etc/php/${PHP_VER}/fpm/pool.d/www.conf"
PHP_INI="/etc/php/${PHP_VER}/fpm/php.ini"
OPCACHE_INI="/etc/php/${PHP_VER}/mods-available/opcache.ini"
MYSQL_CNF="/etc/mysql/mariadb.conf.d/99-webinoly-3gb.cnf"
NGINX_CNF="/etc/nginx/nginx.conf"
NGINX_FASTCGI_TUNING="/etc/nginx/conf.d/99-php-fcgi-timeouts.conf"
NGINX_FASTCGI_CNF="/etc/nginx/conf.d/fastcgi.conf"
PHP_FPM_SLOWLOG="/var/log/php${PHP_VER}-fpm-slow.log"
SYSCTL_CNF="/etc/sysctl.d/99-webinoly-3gb.conf"

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

echo "=== Starting Optimization for 3GB RAM Server ==="

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
set_ini_value "$PHP_POOL" "pm.max_children" "20"
set_ini_value "$PHP_POOL" "pm.start_servers" "6"
set_ini_value "$PHP_POOL" "pm.min_spare_servers" "4"
set_ini_value "$PHP_POOL" "pm.max_spare_servers" "10"
set_ini_value "$PHP_POOL" "pm.max_requests" "400"
set_ini_value "$PHP_POOL" "request_terminate_timeout" "600"
set_ini_value "$PHP_POOL" "listen.backlog" "3072"
set_ini_value "$PHP_POOL" "request_slowlog_timeout" "15s"
set_ini_value "$PHP_POOL" "slowlog" "$PHP_FPM_SLOWLOG"

# ====================== php.ini ======================
echo "== Optimize php.ini =="
set_ini_value "$PHP_INI" "memory_limit" "448M"
set_ini_value "$PHP_INI" "max_execution_time" "600"
set_ini_value "$PHP_INI" "max_input_time" "600"
set_ini_value "$PHP_INI" "max_input_vars" "9000"
set_ini_value "$PHP_INI" "post_max_size" "128M"
set_ini_value "$PHP_INI" "upload_max_filesize" "128M"

# Thêm các thông số tốt
grep -q "^realpath_cache_size" "$PHP_INI" || echo "realpath_cache_size = 3072K" >> "$PHP_INI"
grep -q "^realpath_cache_ttl" "$PHP_INI" || echo "realpath_cache_ttl = 600" >> "$PHP_INI"
grep -q "^opcache.enable" "$PHP_INI" || echo "opcache.enable = 1" >> "$PHP_INI"

# ====================== OPcache ======================
echo "== Optimize OPcache (PHP 8.4) =="
cat > "$OPCACHE_INI" <<'EOF'
zend_extension=opcache.so
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=224
opcache.interned_strings_buffer=24
opcache.max_accelerated_files=70000
opcache.revalidate_freq=0
opcache.validate_timestamps=0
opcache.save_comments=1
opcache.fast_shutdown=1
; JIT - Tracing (mức vừa cho 3GB RAM)
opcache.jit=tracing
opcache.jit_buffer_size=48M
EOF

# ====================== MariaDB ======================
echo "== Optimize MariaDB (3GB Profile) =="
cat > "$MYSQL_CNF" <<'EOF'
[mysqld]
# InnoDB Main Settings
innodb_buffer_pool_size         = 1024M
innodb_buffer_pool_instances    = 2
innodb_log_file_size            = 384M
innodb_log_buffer_size          = 16M
innodb_flush_log_at_trx_commit  = 2
innodb_flush_method             = O_DIRECT
innodb_file_per_table           = 1

# Connection & Thread
max_connections                 = 60
thread_cache_size               = 45
table_open_cache                = 2000
table_definition_cache          = 1600

# Temporary tables
tmp_table_size                  = 48M
max_heap_table_size             = 48M

# Slow Query Log
slow_query_log                  = 1
slow_query_log_file             = /var/log/mysql/slow.log
long_query_time                 = 2

# Other
max_allowed_packet              = 64M
innodb_read_io_threads          = 4
innodb_write_io_threads         = 4
EOF

# ====================== Nginx ======================
echo "== Optimize Nginx =="
sed -i -E \
  -e 's/^[[:space:]]*worker_processes[[:space:]]+[^;]+;/worker_processes auto;/' \
  -e '/^[[:space:]]*worker_rlimit_nofile[[:space:]]+[0-9]+;/d' \
  "$NGINX_CNF"
sed -i '/^[[:space:]]*worker_processes[[:space:]]\+/a worker_rlimit_nofile 65535;' "$NGINX_CNF"

# Thêm một số tối ưu cơ bản (nếu chưa có)
if ! grep -q "client_max_body_size" "$NGINX_CNF"; then
  sed -i '/http {/a \    client_max_body_size 128M;' "$NGINX_CNF"
fi

if [ -f "$NGINX_FASTCGI_CNF" ]; then
  # Webinoly thường có sẵn fastcgi_* trong file này, chỉ cập nhật giá trị để tránh duplicate.
  ensure_single_nginx_directive "$NGINX_FASTCGI_CNF" "fastcgi_connect_timeout" "60s"
  ensure_single_nginx_directive "$NGINX_FASTCGI_CNF" "fastcgi_send_timeout" "600s"
  ensure_single_nginx_directive "$NGINX_FASTCGI_CNF" "fastcgi_read_timeout" "600s"
  [ -f "$NGINX_FASTCGI_TUNING" ] && rm -f "$NGINX_FASTCGI_TUNING"
else
  cat > "$NGINX_FASTCGI_TUNING" <<'EOF'
# Bulk edit và các request admin nặng của WooCommerce có thể vượt quá timeout mặc định 60s.
fastcgi_connect_timeout 60s;
fastcgi_send_timeout 600s;
fastcgi_read_timeout 600s;
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

# ====================== Sysctl ======================
echo "== Sysctl Optimization =="
cat > "$SYSCTL_CNF" <<'EOF'
vm.swappiness = 10
vm.vfs_cache_pressure = 50
net.core.somaxconn = 3072
net.ipv4.tcp_max_syn_backlog = 6144
net.core.netdev_max_backlog = 4096
EOF

# Chỉ apply file sysctl của script để tránh warning từ các file sysctl khác.
sysctl -p "$SYSCTL_CNF" >/dev/null

# ====================== Test & Restart ======================
echo "== Testing configurations =="
php-fpm${PHP_VER} -t && echo "PHP-FPM config: OK"
nginx -t && echo "Nginx config: OK"

echo "== Restarting services =="
systemctl daemon-reload
systemctl restart php${PHP_VER}-fpm
systemctl restart nginx
systemctl restart mariadb

echo "========================================"
echo "DONE! Optimization for 3GB RAM applied."
echo "Khuyến nghị: Theo dõi RAM & load trong 24-48h đầu."
echo "Dùng lệnh: htop, free -h, mysqladmin status"
echo "========================================"
