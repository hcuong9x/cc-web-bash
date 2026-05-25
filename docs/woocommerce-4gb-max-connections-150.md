# WooCommerce 4GB - preset max_connections 150

Tai lieu nay ghi lai cac thay doi trong `optimize-4g-php-fpm-woocommerce.sh` khi toi uu cho VPS 4GB, PHP-FPM 8.4, MariaDB va WooCommerce co dung:

- WooCommerce Advanced Bulk Edit.
- Import san pham tu file CSV.
- Cac tac vu admin dai, it ket noi dong thoi nhung moi request co the nang.

## Muc tieu

- Tang `max_connections` tu 80 len 150 nhung van giu RAM an toan.
- Ho tro import CSV lon hon voi upload 256M.
- Giam loi timeout/buffer khi bulk edit hoac admin request chay lau.
- Giu MariaDB uu tien InnoDB/WooCommerce thay vi mo qua nhieu connection RAM cao.

## Bang so sanh thay doi

| Nhom | Thong so | Truoc | Sau | Ly do |
|---|---:|---:|---:|---|
| PHP ini | `post_max_size` | `128M` | `256M` | Cho phep import CSV/backup nho-vua rong hon. |
| PHP ini | `upload_max_filesize` | `128M` | `256M` | Dong bo voi `post_max_size`. |
| MariaDB | `max_connections` | `80` | `150` | Tang suc chiu burst khi admin/import/cron chay cung luc. |
| MariaDB | `thread_cache_size` | `60` | `80` | Giam chi phi tao thread khi ket noi tang/giam lien tuc. |
| MariaDB | `table_open_cache` | `2500` | `3000` | Tot hon cho WordPress/WooCommerce nhieu bang/plugin. |
| MariaDB | `open_files_limit` | chua set | `65535` | Dam bao `table_open_cache` co du file descriptor. |
| MariaDB | `back_log` | chua set | `150` | Hang doi ket noi phu hop voi `max_connections=150`. |
| MariaDB | `max_connect_errors` | chua set | `100000` | Tranh host bi block qua som khi co loi ket noi tam thoi. |
| MariaDB | `wait_timeout` | default | `60` | Don connection idle nhanh hon de tranh chiem slot. |
| MariaDB | `interactive_timeout` | default | `120` | Giu CLI/admin DB thoang hon `wait_timeout`. |
| MariaDB | `innodb_log_buffer_size` | `16M` | `32M` | Tot hon cho import/bulk update nhieu row. |
| MariaDB | `tmp_table_size` | `64M` | `64M` | Giu suc cho query WooCommerce; khong tang de tranh RAM burst. |
| MariaDB | `max_heap_table_size` | `64M` | `64M` | Dong bo voi `tmp_table_size`. |
| MariaDB | `sort_buffer_size` | default | `1M` | Gioi han RAM moi connection. |
| MariaDB | `join_buffer_size` | default | `1M` | Gioi han RAM moi connection. |
| MariaDB | `read_buffer_size` | default | `512K` | Gioi han RAM moi connection. |
| MariaDB | `read_rnd_buffer_size` | default | `1M` | Gioi han RAM moi connection. |
| MariaDB | `max_allowed_packet` | `64M` | `128M` | An toan hon voi import/meta du lieu lon. |
| nginx | `client_max_body_size` | `128M` | `256M` | Dong bo voi PHP upload/post. |
| nginx | `server_names_hash_bucket_size` | `128` | `512` | Giam loi hostname/domain dai khi `nginx -t`. |
| nginx | `server_names_hash_max_size` | chua set | `2048` | Tot hon khi co nhieu vhost/domain/subdomain. |
| nginx FastCGI | `fastcgi_buffers` | chua set | `8 256k` | Giam loi response/header lon tu PHP admin/plugin. |
| nginx FastCGI | `fastcgi_buffer_size` | chua set | `256k` | Bo dem header/response dau tien lon hon. |
| nginx FastCGI | `fastcgi_busy_buffers_size` | chua set | `256k` | Bo dem khi client doc cham. |
| systemd | MariaDB `LimitNOFILE` | chua set | `65535` | Dong bo voi `open_files_limit`. |

## Gia tri giu nguyen co chu dich

| Thong so | Gia tri | Ly do |
|---|---:|---|
| `innodb_buffer_pool_size` | `1536M` | Khoang 37.5% RAM 4GB, hop ly khi cung chay PHP-FPM/nginx. |
| `innodb_log_file_size` | `512M` | Tot cho write/import WooCommerce, khong qua lon. |
| `tmp_table_size` | `64M` | Can cho query nang; neu tang `max_connections` len 200 thi nen giam xuong 32M. |
| `pm.max_children` | `28` | Gioi han PHP-FPM moi la nguon DB connection chinh cua web. |
| `fastcgi_read_timeout` | `600s` | Can cho bulk edit/import request dai. |
| `memory_limit` | `512M` | Can cho WooCommerce admin/import, khong nen tang neu RAM 4GB. |

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
tail -n 50 /var/log/mysql/slow.log
journalctl -u mariadb -n 100 --no-pager
```

## Nguong danh gia nhanh

| Chi so | Tot | Can theo doi | Nen chinh tiep |
|---|---:|---:|---:|
| `Max_used_connections` | `< 100` | `100-130` | `> 130` thuong xuyen |
| `Threads_connected` luc binh thuong | `< 30` | `30-70` | `> 70` lien tuc |
| RAM available | `> 800M` | `400-800M` | `< 400M` hoac swap tang |
| Swap used | `0-300M` | `300M-1G` | `> 1G` hoac tang lien tuc |
| Slow query | it query `> 2s` | lap lai cung mot query | rat nhieu query trong import/admin |
| `Created_tmp_disk_tables` | tang cham | tang nhanh khi import | tang nhanh ca khi traffic binh thuong |
| `Aborted_connects` | gan 0 | tang nhe | tang lien tuc |

## Huong xu ly theo trieu chung

| Trieu chung | Huong xu ly |
|---|---|
| Het connection, `Max_used_connections` gan 150 | Kiem tra bot/cron/import song song truoc; neu RAM con du co the tang len 180. |
| RAM tut manh, swap tang | Giam `pm.max_children` ve 22-24 hoac giam `tmp_table_size` ve 48M/32M. |
| Import CSV fail vi dung luong file | Neu file >256M, tang dong bo `upload_max_filesize`, `post_max_size`, `client_max_body_size`. |
| Bulk edit bi timeout | Giu `600s`, chia nho batch trong plugin neu van fail. |
| Cap nhat plugin/theme nhung code cu van chay | Restart PHP-FPM de clear OPcache, hoac tam thoi bat `opcache.validate_timestamps=1` trong giai doan setup. |
| Slow log nhieu query WooCommerce meta | Can toi uu index/plugin/query; tang connection khong giai quyet duoc query cham. |

## Ghi chu van hanh

- `max_connections=150` la preset chiu burst, khong co nghia nen co 150 PHP request dong thoi.
- Voi `pm.max_children=28`, web traffic binh thuong thuong chi dung vai chuc DB connection.
- Khi import CSV lon, nen chay luc it traffic va tranh chay nhieu job import/bulk edit cung luc.
- Script co backup cac file cau hinh truoc khi ghi de, ten backup co timestamp.
