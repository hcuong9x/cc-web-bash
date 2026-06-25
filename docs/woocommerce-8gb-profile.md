# WooCommerce 8GB Profile - 4 vCPU, 10+ sites

Profile cho `optimize-8g-php-fpm-woocommerce.sh` toi uu VPS 8GB RAM, 4 vCPU, chay 10+ site WordPress/WooCommerce co dung WooCommerce Advanced Bulk Edit.

## Ngan sach RAM (RAM budget)

| Thanh phan | RAM chiem |
|---|---:|
| OS + system services | ~400MB |
| Nginx (10+ vhosts) | ~50MB |
| OPcache + JIT (shared memory) | 512MB |
| MariaDB (buffer pool + overhead) | ~2860MB |
| **Tong fixed** | **~3822MB** |
| **Con lai cho PHP-FPM workers** | **~4370MB** |

`pm.max_children = 38` duoc chon de giu PHP-FPM trong nguong an toan:
- 38 workers x ~100MB avg = ~3800MB < 4370MB headroom
- Khi WABE spike (200-300MB/worker): du headroom tranh OOM
- `innodb_buffer_pool_size = 2560M` (khong phai 3072M): voi 10+ site nho, pool lon hon khong tang cache hit ratio nhung lam tat RAM cho PHP-FPM

## So sanh voi profile 4GB

| Nhom | Thong so | 4GB | 8GB | Ly do tang |
|---|---:|---:|---:|---|
| PHP-FPM | `pm.max_children` | `18` | `38` | Hon RAM → hon workers |
| PHP-FPM | `pm.start_servers` | `5` | `10` | San sang hon khi burst |
| PHP-FPM | `pm.min_spare_servers` | `4` | `7` | |
| PHP-FPM | `pm.max_spare_servers` | `10` | `20` | |
| PHP-FPM | `pm.max_requests` | `400` | `500` | |
| PHP-FPM | `listen.backlog` | `4096` | `8192` | |
| PHP ini | `memory_limit` | `512M` | `768M` | |
| PHP ini | `post_max_size` | `256M` | `512M` | Import file lon hon |
| PHP ini | `upload_max_filesize` | `256M` | `512M` | |
| PHP ini | `max_input_vars` | `10000` | `15000` | |
| PHP ini | `realpath_cache_size` | `4096K` | `8192K` | |
| OPcache | `memory_consumption` | `256` | `384` | Cache du code hon |
| OPcache | `interned_strings_buffer` | `32` | `48` | |
| OPcache | `max_accelerated_files` | `80000` | `100000` | |
| OPcache | `jit_buffer_size` | `64M` | `128M` | |
| MariaDB | `innodb_buffer_pool_size` | `1536M` | `2560M` | ~31% RAM, de RAM cho PHP |
| MariaDB | `innodb_buffer_pool_instances` | `2` | `4` | 640MB/instance ✓ |
| MariaDB | `innodb_log_file_size` | `512M` | `768M` | |
| MariaDB | `innodb_log_buffer_size` | `32M` | `64M` | |
| MariaDB | `max_connections` | `150` | `220` | |
| MariaDB | `thread_cache_size` | `80` | `120` | |
| MariaDB | `table_open_cache` | `3000` | `5000` | |
| MariaDB | `table_definition_cache` | `2000` | `3000` | |
| MariaDB | `back_log` | `150` | `220` | |
| MariaDB | `tmp_table_size` | `64M` | `96M` | |
| MariaDB | `max_heap_table_size` | `64M` | `96M` | |
| MariaDB | `max_allowed_packet` | `128M` | `256M` | |
| Nginx | `client_max_body_size` | `256M` | `512M` | |
| sysctl | `net.core.somaxconn` | `4096` | `8192` | |
| sysctl | `net.ipv4.tcp_max_syn_backlog` | `8192` | `16384` | |
| sysctl | `net.core.netdev_max_backlog` | `5000` | `8192` | |

## Gia tri giu nguyen co chu dich

| Thong so | Gia tri | Ly do |
|---|---:|---|
| `innodb_buffer_pool_instances` | `4` | 2560M/4 = 640MB/instance, dung guideline |
| `innodb_flush_log_at_trx_commit` | `2` | Can bang toc do write vs do ben du lieu |
| `innodb_flush_method` | `O_DIRECT` | Tranh double buffering voi InnoDB pool lon |
| `wait_timeout` | `60` | Don connection idle nhanh tranh chiem slot |
| `sort_buffer_size` | `1M` | Gioi han RAM moi connection (220 connections) |
| `fastcgi_read_timeout` | `600s` | WABE bulk edit / import CSV dai |
| `opcache.validate_timestamps` | `0` | **Restart PHP-FPM sau khi update plugin/theme** |

## Lua chon nang cao

| Dieu kien | Co the chinh |
|---|---|
| 1 site WooCommerce lon, RAM available lien tuc > 2G | Tang `innodb_buffer_pool_size` len `3072M` |
| `Max_used_connections` > 180 lien tuc, RAM con du | Tang `max_connections` len 250 |
| RAM tut manh khi WABE/import | Giam `pm.max_children` ve 32-34 truoc khi dieu chinh MariaDB |
| Nhieu tmp disk tables khi import | Tang `tmp_table_size` len 128M neu RAM available > 1.5G |

## Theo doi sau khi chay

```bash
free -h
mysqladmin status
mysql -e "SHOW GLOBAL STATUS LIKE 'Max_used_connections';"
mysql -e "SHOW GLOBAL STATUS LIKE 'Threads_connected';"
mysql -e "SHOW GLOBAL STATUS LIKE 'Created_tmp_disk_tables';"
mysql -e "SHOW GLOBAL STATUS LIKE 'Aborted_connects';"
mysql -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"
tail -n 50 /var/log/mysql/slow.log
journalctl -u mariadb -n 100 --no-pager
```

## Nguong danh gia nhanh

| Chi so | Tot | Can theo doi | Nen chinh tiep |
|---|---|---|---|
| `Max_used_connections` | < 120 | 120-190 | > 190 thuong xuyen |
| `Threads_connected` binh thuong | < 40 | 40-90 | > 90 lien tuc |
| RAM available | > 1.5G | 800MB-1.5G | < 800MB hoac swap tang |
| Swap used | 0-300MB | 300MB-1G | > 1G hoac tang lien tuc |

## Luu y van hanh

- `opcache.validate_timestamps=0`: Sau moi lan cap nhat plugin/theme/core → **phai chay `systemctl restart php8.4-fpm`**.
- `max_connections=220` la ceiling chiu burst, khong phai muc hoat dong thuong xuyen.
- Khong chay WABE bulk edit dong thoi tren nhieu site — moi worker co the spike 200-300MB.
- Script backup tat ca file config truoc khi ghi de voi timestamp.
