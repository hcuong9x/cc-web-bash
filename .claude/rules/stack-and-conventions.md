---
description: Webinoly server stack, WordPress site layout, and bash scripting conventions shared across all scripts
alwaysApply: true
---

## Server stack

Ubuntu 24.04 + Webinoly: Nginx + PHP-FPM 8.4 + MariaDB.

WordPress sites live at `/var/www/<domain>/htdocs`. The `wp-config.php` is one level up at `/var/www/<domain>/wp-config.php`.

## WP-CLI conventions

Always pass `--allow-root` — scripts are designed to run as root on the server.

```bash
wp plugin install all-in-one-wp-migration --activate --allow-root
wp ai1wm restore backup.wpress --allow-root
```

## Permission handling pattern

Detect owner/group before touching a directory, restore it after:

```bash
OWNER_GROUP="$(stat -c "%U:%G" "$WP_PATH")"
# ... do work ...
sudo chown -R "$OWNER_GROUP" "$WP_PATH"
```

WordPress web-serving directories are ultimately owned by `www-data:www-data`. Dirs `755`, files `644`.

## Temporary directories

Per-domain temp dirs use `/tmp/wp-restore-<domain>`. Always cleaned up on success or failure (via `trap` or explicit `rm -rf`).

## Git-ignored files

`.wpress` backup files are git-ignored — never commit them. Also ignored: `tino script/`, `idea.txt`, `note.txt`.

## Bundled zip files (must stay in repo)

| File | Used by | Purpose |
|---|---|---|
| `all-in-one-wp-migration-url-extension.zip` | `clone-template.sh`, `301_website.sh` | Removes size limit on `.wpress` restores |
| `simple-website-redirect.zip` | `301_website.sh` | Configures 301 redirect on old domain |

If either zip is missing, the script that needs it will fail with an explicit error message.
