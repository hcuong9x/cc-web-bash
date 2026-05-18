# Tong ket va exit code

Tinh nang nay giup biet domain nao clone thanh cong va domain nao bi loi sau khi chay nhieu domain.

## Tong ket cuoi lenh

Sau khi chay xong tat ca domain, script in thong tin:

```text
Clone summary
Successful: <so luong>
  domain-thanh-cong.com
Failed: <so luong>
  domain-that-bai.com
```

## Exit code

- Neu tat ca domain thanh cong, script tra ve exit code `0`.
- Neu co it nhat mot domain that bai, script tra ve exit code `1`.

Dieu nay giup dung script trong automation hoac CI de phat hien loi.

## Hanh vi khi gap loi

- Loi cua mot domain khong dung toan bo qua trinh.
- Script tiep tuc restore cac domain con lai.
- Thu muc tam cua domain bi loi se duoc xoa neu loi di qua ham xu ly loi cua script.
