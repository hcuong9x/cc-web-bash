# Backup tu Google Drive

Tinh nang nay cho phep download file backup tu Google Drive bang File ID, sau do restore cho mot hoac nhieu domain.

## Cach dung khuyen nghi

```bash
./clone-template.sh --google-file-id GOOGLE_FILE_ID domain1.com domain2.com
```

Co the dung alias ngan hon:

```bash
./clone-template.sh --file-id GOOGLE_FILE_ID domain1.com domain2.com
```

## Tuong thich cach cu

Script van ho tro cach truyen File ID o cuoi lenh:

```bash
./clone-template.sh example.com GOOGLE_FILE_ID
```

Voi nhieu domain:

```bash
./clone-template.sh domain1.com domain2.com GOOGLE_FILE_ID
```

## Cach hoat dong

- Script kiem tra lenh `gdown`.
- Neu chua co `gdown`, script cai `python3-pip` va `gdown`.
- File Google Drive duoc tai ve mot lan vao thu muc tam.
- Cung file backup do duoc dung de restore lan luot tung domain.

## Luu y

- File tren Google Drive can co quyen truy cap phu hop de `gdown` tai ve duoc.
- Neu vua co `--file` vua co `--google-file-id`, script se bao loi de tranh nham source backup.
