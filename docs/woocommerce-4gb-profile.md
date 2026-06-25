# WooCommerce 4GB Profile - 2 vCPU, 10+ sites

Profile cho `optimize-4g-php-fpm-woocommerce.sh` toi uu VPS 4GB RAM, 2 vCPU, chay 10+ site WordPress/WooCommerce co dung WooCommerce Advanced Bulk Edit.

## Ngan sach RAM (RAM budget)

| Thanh phan | RAM chiem |
|---|---:|
| OS + system services | ~350MB |
| Nginx (10+ vhosts) | ~40MB |
| OPcache + JIT (shared memory) | 320MB |
| MariaDB (buffer pool + overhead) | ~1736MB |
| **Tong fixed** | **~2446MB** |
| **Con lai cho PHP-FPM workers** | **~1650MB** |

`pm.max_children = 18` duoc chon de giu PHP-FPM trong nguong an toan:
- 18 workers x ~90MB avg = ~1620MB < 1650MB headroom
- Khi WABE spike (200-300MB/worker): du so luong workers bi gioi han tranh OOM killer

## Thong so chinh

### PHP-FPM

| Thong so | Gia tri | Ghi chu |
|---|---:|---|
| `pm` | `dynamic` | Phu hop traffic dao dong |
| `pm.max_children` | `18` | Gioi han boi RAM, khong phai CPU (I/O-bound) |
| `pm.start_servers` | `5` | Khoi dong san sang vua du |
| `pm.min_spare_servers` | `4` | Worker ranh toi thieu |
| `pm.max_spare_servers` | `10` | Giu RAM khi traffic thap |
| `pm.max_requests` | `400` | Tai che worker dinh ky de han che memory leak |
| `request_terminate_timeout` | `600` | Du cho WABE bulk edit dai |
| `listen.backlog` | `4096` | Hang doi request khi tat ca worker ban |

### PHP.ini

| Thong so | Gia tri |
|---|---:|
| `memory_limit` | `512M` |
| `max_execution_time` | `600` |
| `max_input_vars` | `10000` |
| `post_max_size` | `256M` |
| `upload_max_filesize` | `256M` |
| `realpath_cache_size` | `4096K` |

### OPcache

| Thong so | Gia tri | Ghi chu |
|---|---:|---|
| `opcache.memory_consumption` | `256` | Shared memory, du cho 10+ site WP |
| `opcache.interned_strings_buffer` | `32` | |
| `opcache.max_accelerated_files` | `80000` | WP + WooCommerce + nhieu plugin |
| `opcache.validate_timestamps` | `0` | **Phai restart PHP-FPM sau khi update plugin/theme** |
| `opcache.jit` | `tracing` | JIT PHP 8.4 |
| `opcache.jit_buffer_size` | `64M` | Shared memory |

### MariaDB

| Thong so | Gia tri | Ghi chu |
|---|---:|---|
| `innodb_buffer_pool_size` | `1536M` | 37.5% RAM — hop ly cho multi-site |
| `innodb_buffer_pool_instances` | `2` | 768MB/instance, dung guideline >= 512MB |
| `innodb_log_file_size` | `512M` | Tot cho WooCommerce write/import |
| `innodb_flush_log_at_trx_commit` | `2` | Can bang toc do vs an toan |
| `max_connections` | `150` | ~3x headroom cho 18 PHP workers + cron + WP-CLI |
| `wait_timeout` | `60` | Don connection idle de tranh chiem slot |
| `tmp_table_size` | `64M` | Du cho WooCommerce query |
| `max_allowed_packet` | `128M` | |

### Nginx FastCGI

| Thong so | Gia tri | Ghi chu |
|---|---:|---|
| `fastcgi_read_timeout` | `600s` | WABE bulk edit chay lau |
| `fastcgi_buffers` | `8 256k` | 2MB buffer cho response lon |
| `fastcgi_buffer_size` | `256k` | |
| `fastcgi_busy_buffers_size` | `512k` | = 2x buffer_size (Nginx default) |
| `client_max_body_size` | `256M` | Dong bo voi PHP upload |

## Theo doi sau khi chay

```bash
# RAM tong the
free -h

# MariaDB connections thuc te
mysql -e "SHOW GLOBAL STATUS LIKE 'Max_used_connections';"
mysql -e "SHOW GLOBAL STATUS LIKE 'Threads_connected';"

# PHP-FPM workers dang chay
ps aux | grep php-fpm | grep -v grep | wc -l

# Slow query
tail -n 50 /var/log/mysql/slow.log

# Journal MariaDB
journalctl -u mariadb -n 50 --no-pager
```

## Nguong danh gia nhanh

| Chi so | Tot | Can theo doi | Nen chinh tiep |
|---|---|---|---|
| `Max_used_connections` | < 60 | 60-120 | > 120 thuong xuyen |
| RAM available | > 800MB | 400-800MB | < 400MB hoac swap tang |
| Swap used | 0-200MB | 200-500MB | > 500MB hoac tang lien tuc |

## Luu y van hanh

- `opcache.validate_timestamps=0`: Sau moi lan cap nhat plugin/theme/core → **phai chay `systemctl restart php8.4-fpm`** de clear OPcache.
- Khong nen chay WABE bulk edit dong thoi tren nhieu site vi moi worker co the spike len 200-300MB.
- Script backup cac file config truoc khi ghi de, ten backup co timestamp.
