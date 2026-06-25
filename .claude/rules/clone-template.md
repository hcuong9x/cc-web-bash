---
description: How clone-template.sh works — invocation modes, prerequisites, restore workflow, and multi-domain behavior
globs:
  - clone-template.sh
---

## Purpose

Restores one or more WordPress sites from a single `.wpress` backup. The same backup is applied to every domain in the same run.

## Invocation

```bash
# Auto-detect .wpress in script dir (prompts if multiple found)
./clone-template.sh domain1.com domain2.com

# Local file — trailing arg or explicit flag
./clone-template.sh domain1.com domain2.com backup.wpress
./clone-template.sh --file backup.wpress domain1.com domain2.com

# Google Drive (downloads via gdown; installs gdown automatically if missing)
./clone-template.sh --google-file-id GOOGLE_FILE_ID domain1.com domain2.com
./clone-template.sh --file-id GOOGLE_FILE_ID domain1.com          # alias
```

`--file` and `--google-file-id` are mutually exclusive.

## Prerequisites per domain

- Site already created: `sudo site domain.com -wp`
- `wp-config.php` exists at `/var/www/<domain>/wp-config.php`
- `all-in-one-wp-migration-url-extension.zip` present in the script directory

## Restore workflow (per domain)

1. Copy backup source → `/tmp/wp-restore-<domain>/<domain>.wpress`
2. Verify WordPress site at `/var/www/<domain>/htdocs`
3. `wp plugin delete --all --allow-root` — wipe existing plugins
4. Install + activate `all-in-one-wp-migration`
5. Install + activate `all-in-one-wp-migration-url-extension.zip`
6. Copy `.wpress` → `wp-content/ai1wm-backups/`
7. `printf 'y\n' | wp ai1wm restore <domain>.wpress --allow-root`
8. Delete the copied `.wpress` from `ai1wm-backups/`
9. Reset permissions: `www-data:www-data`, dirs `755`, files `644`
10. Remove `/tmp/wp-restore-<domain>`

## Multi-domain behavior and exit codes

- A failure on one domain **does not stop** the remaining domains.
- End-of-run summary lists successful and failed domains.
- Exit code `0` if all domains succeeded; `1` if any domain failed.
- Google Drive backup is downloaded once; the same local copy is reused for all domains.
- Source temp dir (`/tmp/wp-restore-source-$$`) is removed via `trap EXIT` when using Google Drive.
