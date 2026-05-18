# Chon file .wpress

Tinh nang nay cho phep chi dinh file backup `.wpress` can restore.

## Cach 1: truyen file o cuoi lenh

```bash
./clone-template.sh domain1.com domain2.com backup.wpress
```

Script se hieu tham so cuoi cung co duoi `.wpress` la file backup.

## Cach 2: dung --file

```bash
./clone-template.sh --file backup.wpress domain1.com domain2.com
```

Co the dung duong dan tuong doi, duong dan tuyet doi, hoac ten file nam trong cung thu muc voi script.

## Cach 3: tu dong tim file

Neu khong truyen file `.wpress`, script se tim cac file `.wpress` trong thu muc chua `clone-template.sh`.

- Neu chi co 1 file `.wpress`, script tu dong dung file do.
- Neu co nhieu file `.wpress`, script hien menu de chon.
- Neu chay trong moi truong khong co terminal tuong tac, nen dung `--file` de chi dinh file ro rang.

## Vi du

```bash
./clone-template.sh example.com
./clone-template.sh example.com template.wpress
./clone-template.sh --file /backup/template.wpress example.com
```
