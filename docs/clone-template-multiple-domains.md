# Clone nhieu domain

Tinh nang nay cho phep `clone-template.sh` restore cung mot file backup cho nhieu domain trong mot lan chay.

## Cach dung

```bash
./clone-template.sh domain1.com domain2.com domain3.com file.wpress
```

Hoac dung tham so ro rang hon:

```bash
./clone-template.sh --file file.wpress domain1.com domain2.com domain3.com
```

## Cach hoat dong

- Script chuan bi file backup mot lan.
- Sau do chay restore lan luot tung domain.
- Neu mot domain bi loi, script ghi nhan domain do that bai va tiep tuc voi domain tiep theo.
- Cuoi qua trinh, script in bang tong ket domain thanh cong va domain that bai.

## Dieu kien

- Moi domain phai co san WordPress site tai `/var/www/<domain>/htdocs`.
- Moi site can co file `/var/www/<domain>/wp-config.php`.
- Domain nen duoc tao truoc bang lenh:

```bash
sudo site domain.com -wp
```
