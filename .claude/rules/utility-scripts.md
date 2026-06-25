---
description: Quick reference for the smaller utility scripts — site creation, plugin cleanup, WP-CLI install, Zabbix, user management, and backup/restore
globs:
  - clone_web.sh
  - delete-plugin-zips.sh
  - install-wp-cli.sh
  - install-zabbix-agent.sh
  - update_user_pw.sh
  - backup-wp.sh
  - restore-wp.sh
---

## clone_web.sh

Creates new WordPress sites via Webinoly for one or more domains.

```bash
./clone_web.sh domain1.com domain2.com
```

Runs per domain: `site <domain> -wp` → `httpauth <domain> -wp-admin=off` → `site <domain> -ssl=on`.

## delete-plugin-zips.sh

Removes leftover `.zip` files from `/var/www/*/htdocs/wp-content/plugins`.

```bash
./delete-plugin-zips.sh --dry-run          # preview only
./delete-plugin-zips.sh --force            # delete without prompt
./delete-plugin-zips.sh --recursive --force  # also scan plugin subfolders
```

## install-wp-cli.sh

Downloads `wp-cli.phar`, tests it with PHP, and installs to `/usr/local/bin/wp`.

```bash
./install-wp-cli.sh
```

Prompts to confirm if WP-CLI is already installed (can be used to update).

## install-zabbix-agent.sh

Installs Zabbix agent 6.0 on Ubuntu 22.04 and points it at `zabbix.cd-site.com`.

```bash
sudo ./install-zabbix-agent.sh <hostname>
# Example: sudo ./install-zabbix-agent.sh Host-Ram-IP
```

Edits `/etc/zabbix/zabbix_agentd.conf` for `Server`, `ServerActive`, and `Hostname`, then enables the service.

## backup-wp.sh

Backs up one or more WordPress sites (Webinoly stack) to `.tgz` archives — no plugin required. Each archive contains `files.tar.gz` + `db.sql` + `meta.env`. Optionally uploads to Google Drive via rclone.

```bash
./backup-wp.sh example.com                                         # local backup only
./backup-wp.sh --gdrive-folder-id FOLDER_ID site1.com site2.com   # backup + upload
./backup-wp.sh --exclude-uploads --output-dir /mnt/backup site.com
```

**Archive format:** `<domain>-YYYYMMDD-HHMMSS.tgz`
- `files.tar.gz` — WordPress docroot, excluding `wp-content/cache` and `wp-content/ai1wm-backups`
- `db.sql` — full database dump via `wp db export --add-drop-table`
- `meta.env` — `SOURCE_DOMAIN`, `SOURCE_SITEURL`, `SOURCE_HOME`, `SOURCE_TABLE_PREFIX`, `BACKUP_CREATED_AT`

**Google Drive upload:** requires rclone with a remote named `gdrive` (configurable via `--rclone-remote`). Script guides through setup if rclone is missing or the remote is not configured.

Options: `--output-dir DIR`, `--gdrive-folder-id ID`, `--rclone-remote NAME`, `--exclude-uploads`, `--maintenance`.

## restore-wp.sh

Restores one or more WordPress sites from a `.tgz` archive created by `backup-wp.sh`. The same backup is applied to every listed domain. URLs are automatically search-replaced from source to target domain.

```bash
./restore-wp.sh --file backup.tgz example.com
./restore-wp.sh --gdrive-file-id FILE_ID site1.com site2.com      # gdown auto-installed
./restore-wp.sh --file template.tgz --source-domain template.com new1.com new2.com
```

**Prerequisites per domain:** site must exist (`sudo site <domain> -wp`) and `wp-config.php` must be at `/var/www/<domain>/wp-config.php`.

**Restore workflow per domain:**
1. Extract archive → validate `files.tar.gz`, `db.sql`, `meta.env`
2. Read source domain/URLs from metadata
3. Wipe `/var/www/<domain>/htdocs` (preserves `.well-known`)
4. Extract `files.tar.gz` to docroot
5. `wp db reset` + `wp db import db.sql`
6. `wp search-replace` source URLs → `https://<target-domain>`
7. Fix permissions (`www-data:www-data`, dirs `755`, files `644`)

Options: `--file PATH`, `--gdrive-file-id ID`, `--source-domain DOMAIN`, `--maintenance`, `--keep-uploads`.

## update_user_pw.sh

Updates a WordPress user's password via WP-CLI directly (no longer uses Webinoly).

```bash
# Non-interactive (all args provided)
./update_user_pw.sh <domain-or-url> <username> <new_password>

# Interactive (prompts for missing args, asks for confirmation)
./update_user_pw.sh
```

Accepts a full URL or bare domain — strips protocol/path automatically. Validates the domain format before proceeding. Wraps: `wp user update "$USERNAME" --user_pass="$PASSWORD" --allow-root`.
