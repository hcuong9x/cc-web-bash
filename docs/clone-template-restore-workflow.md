# Quy trinh restore WordPress

File nay mo ta cac buoc restore ma `clone-template.sh` thuc hien cho moi domain.

## Cac buoc chinh

1. Tao thu muc tam rieng cho domain tai `/tmp/wp-restore-<domain>`.
2. Copy file backup source thanh `<domain>.wpress`.
3. Kiem tra WordPress site tai `/var/www/<domain>/htdocs`.
4. Kiem tra file `/var/www/<domain>/wp-config.php`.
5. Xoa plugin cu bang `wp plugin delete --all --allow-root`.
6. Cai va kich hoat plugin `all-in-one-wp-migration`.
7. Cai va kich hoat extension `all-in-one-wp-migration-url-extension.zip`.
8. Copy file `.wpress` vao `wp-content/ai1wm-backups`.
9. Chay restore bang WP-CLI va tu dong xac nhan prompt proceed:

```bash
printf 'y\n' | wp ai1wm restore <domain>.wpress --allow-root
```

10. Xoa file backup vua copy sau khi restore thanh cong.
11. Set lai owner va permission cho WordPress site.
12. Xoa thu muc tam cua domain.

## File can co

Extension zip phai nam cung thu muc voi script:

```text
all-in-one-wp-migration-url-extension.zip
```

Neu file nay khong ton tai, domain dang restore se bi danh dau that bai.
