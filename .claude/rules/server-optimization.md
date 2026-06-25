---
description: How the optimize-{2g,3g,4g,8g}-php-fpm-woocommerce.sh scripts work — what they tune, safety patterns, and RAM-variant differences
globs:
  - optimize-*.sh
---

## Purpose

Tune a Webinoly server for WooCommerce workloads (bulk edit, CSV import, long admin requests). Must run as root.

## What each script tunes

| Layer | Config file |
|---|---|
| PHP-FPM pool | `/etc/php/8.4/fpm/pool.d/www.conf` |
| php.ini | `/etc/php/8.4/fpm/php.ini` |
| OPcache | `/etc/php/8.4/mods-available/opcache.ini` |
| MariaDB | `/etc/mysql/mariadb.conf.d/99-webinoly-*.cnf` |
| Nginx main | `/etc/nginx/nginx.conf` |
| Nginx FastCGI | `/etc/nginx/conf.d/fastcgi.conf` or `99-php-fcgi-timeouts.conf` |
| System limits | `/etc/security/limits.d/99-webinoly.conf` + systemd overrides |
| Sysctl | `/etc/sysctl.d/99-webinoly-{4gb,8gb}.conf` |

## Safety patterns

- **Backup before write**: every config file is copied with a timestamp suffix (`file.bak.YYYY-MM-DD-HHMMSS`) before modification.
- **Test before restart**: `php-fpm8.4 -t` and `nginx -t` are run; the script exits on failure before touching any service.
- Helper `set_ini_value` handles both commented-out and missing keys cleanly via `sed`.
- `ensure_single_nginx_directive` prevents duplicate directives by deleting existing lines before appending.

## Key values by RAM variant

| Setting | 4g | 8g |
|---|---:|---:|
| `pm.max_children` | 18 | 38 |
| `pm.start_servers` | 5 | 10 |
| `pm.min_spare_servers` | 4 | 7 |
| `pm.max_spare_servers` | 10 | 20 |
| `memory_limit` | 512M | 768M |
| `post_max_size` / `upload_max_filesize` | 256M | 512M |
| `client_max_body_size` (Nginx) | 256M | 512M |
| `innodb_buffer_pool_size` | 1536M | 2560M |
| `innodb_buffer_pool_instances` | 2 | 4 |
| `max_connections` | 150 | 220 |
| OPcache `memory_consumption` | 256M | 384M |
| OPcache `jit_buffer_size` | 64M | 128M |
| MariaDB config file | `99-webinoly-4gb.cnf` | `99-webinoly-8gb.cnf` |
| `net.core.somaxconn` | 4096 | 8192 |

All variants enable OPcache JIT (`opcache.jit=tracing`) and `fastcgi_read_timeout 600s`.

See `docs/woocommerce-4gb-profile.md` and `docs/woocommerce-8gb-profile.md` for full rationale, comparison tables, and monitoring queries per variant.

## Post-run monitoring

```bash
free -h
mysqladmin status
mysql -e "SHOW GLOBAL STATUS LIKE 'Max_used_connections';"
mysql -e "SHOW GLOBAL STATUS LIKE 'Threads_connected';"
tail -n 50 /var/log/mysql/slow.log
```
