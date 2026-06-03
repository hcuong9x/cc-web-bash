# WooCommerce 8GB - preset max_connections 220

Tai lieu nay ghi lai profile de xuat cho `optimize-8g-php-fpm-woocommerce.sh` khi toi uu VPS 8GB, PHP-FPM 8.4, MariaDB va WooCommerce co dung:

- WooCommerce Advanced Bulk Edit.
- Import san pham tu file CSV lon hon.
- Cac tac vu admin dai, cron/import chay cung luc, moi request co the nang.

## Muc tieu

- Tang suc chiu burst so voi profile 4GB nhung khong nhan doi moi thong so.
- Uu tien RAM cho InnoDB/WooCommerce thay vi mo qua nhieu PHP worker.
- Ho tro import CSV/backup nho-vua lon hon voi upload 512M.
- Giu per-connection buffer MariaDB thap de tranh RAM tang dot bien khi `max_connections=220`.
- Giam loi timeout/buffer khi bulk edit hoac admin request chay lau.

## Bang so sanh thay doi tu profile 4GB

| Nhom | Thong so | 4GB | 8GB | Ly do |
|---|---:|---:|---:|---|
| PHP-FPM | `pm.max_children` | `28` | `44` | Tang suc xu ly request PHP dong thoi nhung van tranh an het RAM khi WooCommerce request nang. |
| PHP-FPM | `pm.start_servers` | `8` | `12` | San sang hon khi co burst traffic/admin. |
| PHP-FPM | `pm.min_spare_servers` | `6` | `8` | Giu worker ranh toi thieu hop ly. |
| PHP-FPM | `pm.max_spare_servers` | `16` | `24` | Giam tao/huy process khi traffic dao dong. |
| PHP-FPM | `pm.max_requests` | `400` | `500` | Tai che worker dinh ky de han che leak nho nhe. |
| PHP-FPM | `listen.backlog` | `4096` | `8192` | Hang doi PHP-FPM lon hon khi request tang dot bien. |
| PHP ini | `memory_limit` | `512M` | `768M` | Rong hon cho import/admin nang, nhung khong dat 1G de tranh RAM burst. |
| PHP ini | `post_max_size` | `256M` | `512M` | Ho tro upload/import file lon hon. |
| PHP ini | `upload_max_filesize` | `256M` | `512M` | Dong bo voi `post_max_size`. |
| PHP ini | `max_input_vars` | `10000` | `15000` | Tot hon cho admin/form/plugin nhieu field. |
| PHP ini | `realpath_cache_size` | `4096K` | `8192K` | Tot hon cho WordPress/WooCommerce nhieu plugin/file. |
| OPcache | `memory_consumption` | `256` | `384` | Cache du code hon khi nhieu plugin/theme. |
| OPcache | `interned_strings_buffer` | `32` | `48` | Tot hon cho WordPress/WooCommerce nhieu chuoi. |
| OPcache | `max_accelerated_files` | `80000` | `100000` | Du headroom cho site nhieu plugin. |
| OPcache | `jit_buffer_size` | `64M` | `128M` | Tang buffer JIT khi RAM du hon. |
| MariaDB | `innodb_buffer_pool_size` | `1536M` | `3072M` | Khoang 37.5% RAM 8GB, uu tien InnoDB nhung van de RAM cho PHP-FPM/nginx/system. |
| MariaDB | `innodb_log_file_size` | `512M` | `768M` | Tot hon cho import/bulk update nhieu row. |
| MariaDB | `innodb_log_buffer_size` | `32M` | `64M` | Giam flush khi transaction/import lon. |
| MariaDB | `max_connections` | `150` | `220` | Tang suc chiu burst khi admin/import/cron chay cung luc. |
| MariaDB | `thread_cache_size` | `80` | `120` | Giam chi phi tao thread khi connection tang/giam lien tuc. |
| MariaDB | `table_open_cache` | `3000` | `5000` | Tot hon cho WordPress/WooCommerce nhieu bang/plugin. |
| MariaDB | `table_definition_cache` | `2000` | `3000` | Dong bo voi table cache lon hon. |
| MariaDB | `back_log` | `150` | `220` | Hang doi ket noi phu hop voi `max_connections=220`. |
| MariaDB | `tmp_table_size` | `64M` | `96M` | Rong hon cho query/import nang, nhung chua tang len 128M de tranh RAM burst. |
| MariaDB | `max_heap_table_size` | `64M` | `96M` | Dong bo voi `tmp_table_size`. |
| MariaDB | `max_allowed_packet` | `128M` | `256M` | An toan hon voi import/meta du lieu lon. |
| nginx | `client_max_body_size` | `256M` | `512M` | Dong bo voi PHP upload/post. |
| sysctl | `net.core.somaxconn` | `4096` | `8192` | Hang doi socket lon hon. |
| sysctl | `net.ipv4.tcp_max_syn_backlog` | `8192` | `16384` | Chiu burst ket noi TCP tot hon. |
| sysctl | `net.core.netdev_max_backlog` | `5000` | `8192` | Hang doi network packet lon hon. |

## Gia tri giu nguyen co chu dich

| Thong so | Gia tri | Ly do |
|---|---:|---|
| `innodb_buffer_pool_instances` | `4` | Du cho buffer pool 3GB; khong can tang neu khong co bang chung tranh cao. |
| `innodb_flush_log_at_trx_commit` | `2` | Can bang giua toc do import/write va do ben du lieu. |
| `innodb_flush_method` | `O_DIRECT` | Giam double buffering khi dung InnoDB buffer pool lon. |
| `wait_timeout` | `60` | Don connection idle nhanh hon de tranh chiem slot. |
| `interactive_timeout` | `120` | Giu CLI/admin DB thoang hon `wait_timeout`. |
| `sort_buffer_size` | `1M` | Gioi han RAM moi connection. |
| `join_buffer_size` | `1M` | Gioi han RAM moi connection. |
| `read_buffer_size` | `512K` | Gioi han RAM moi connection. |
| `read_rnd_buffer_size` | `1M` | Gioi han RAM moi connection. |
| `fastcgi_read_timeout` | `600s` | Can cho bulk edit/import request dai. |
| `server_names_hash_bucket_size` | `512` | Giam loi hostname/domain dai khi `nginx -t`. |
| `server_names_hash_max_size` | `2048` | Tot hon khi co nhieu vhost/domain/subdomain. |

## Lua chon nang cao

| Dieu kien | Co the chinh |
|---|---|
| Server chu yeu chay 1 site WooCommerce, RAM available luon tren `1.5G` | Tang `innodb_buffer_pool_size` len `3584M`. |
| `Max_used_connections` thuong xuyen tren `180`, RAM available van tren `1.5G` | Tang `max_connections` len `250`. |
| RAM tut manh khi import/admin, swap tang | Giam `pm.max_children` ve `36-40` truoc khi giam MariaDB. |
| Nhieu temporary table ra disk trong import | Thu tang `tmp_table_size` va `max_heap_table_size` len `128M`, chi lam khi RAM con du. |

## Cach theo doi sau khi chay

Chay cac lenh nay sau import/bulk edit, va lap lai trong 24-48h dau:

```bash
free -h
mysqladmin status
mysql -e "SHOW GLOBAL STATUS LIKE 'Max_used_connections';"
mysql -e "SHOW GLOBAL STATUS LIKE 'Threads_connected';"
mysql -e "SHOW GLOBAL STATUS LIKE 'Created_tmp_disk_tables';"
mysql -e "SHOW GLOBAL STATUS LIKE 'Aborted_connects';"
mysql -e "SHOW VARIABLES LIKE 'max_connections';"
mysql -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"
tail -n 50 /var/log/mysql/slow.log
journalctl -u mariadb -n 100 --no-pager
```

## Nguong danh gia nhanh

| Chi so | Tot | Can theo doi | Nen chinh tiep |
|---|---:|---:|---:|
| `Max_used_connections` | `< 150` | `150-190` | `> 190` thuong xuyen |
| `Threads_connected` luc binh thuong | `< 45` | `45-100` | `> 100` lien tuc |
| RAM available | `> 1.5G` | `800M-1.5G` | `< 800M` hoac swap tang |
| Swap used | `0-300M` | `300M-1G` | `> 1G` hoac tang lien tuc |
| Slow query | it query `> 2s` | lap lai cung mot query | rat nhieu query trong import/admin |
| `Created_tmp_disk_tables` | tang cham | tang nhanh khi import | tang nhanh ca khi traffic binh thuong |
| `Aborted_connects` | gan 0 | tang nhe | tang lien tuc |

## Huong xu ly theo trieu chung

| Trieu chung | Huong xu ly |
|---|---|
| Het connection, `Max_used_connections` gan 220 | Kiem tra bot/cron/import song song truoc; neu RAM con du co the tang len 250. |
| RAM tut manh, swap tang | Giam `pm.max_children` ve `36-40` hoac giam `tmp_table_size` ve `64M`. |
| Import CSV fail vi dung luong file | Neu file >512M, tang dong bo `upload_max_filesize`, `post_max_size`, `client_max_body_size`. |
| Bulk edit bi timeout | Giu `600s`, chia nho batch trong plugin neu van fail. |
| Cap nhat plugin/theme nhung code cu van chay | Restart PHP-FPM de clear OPcache, hoac tam thoi bat `opcache.validate_timestamps=1` trong giai doan setup. |
| Slow log nhieu query WooCommerce meta | Can toi uu index/plugin/query; tang connection khong giai quyet duoc query cham. |

## Ghi chu van hanh

- `max_connections=220` la preset chiu burst, khong co nghia nen co 220 PHP request dong thoi.
- Voi `pm.max_children=44`, web traffic binh thuong thuong chi dung vai chuc DB connection.
- Khi import CSV lon, nen chay luc it traffic va tranh chay nhieu job import/bulk edit cung luc.
- Script co backup cac file cau hinh truoc khi ghi de, ten backup co timestamp.
