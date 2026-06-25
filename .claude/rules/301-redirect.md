---
description: How 301_website.sh works — migrating content between domains and configuring a permanent redirect
globs:
  - 301_website.sh
---

## Purpose

Migrates a WordPress site's content from `old_domain` to `new_domain`, then installs a 301 redirect on the old domain pointing to the new one.

## Usage

```bash
./301_website.sh old_domain.com new_domain.com [slug]
# slug defaults to 'htdocs'
```

Both domains must already have WordPress sites set up at `/var/www/<domain>/<slug>`.

## Workflow

1. **Backup** `old_domain` — installs/updates `all-in-one-wp-migration` + URL extension, removes old `.wpress` files, runs `wp ai1wm backup --sites --allow-root --exclude-cache`.
2. **Move** the generated `.wpress` from `old_domain`'s `ai1wm-backups/` to `new_domain`'s `ai1wm-backups/`.
3. **Restore** on `new_domain` — same plugin setup, runs `wp ai1wm restore <file> --allow-root`, then resets owner.
4. **Configure 301** on `old_domain`:
   - Deactivates ai1wm plugins
   - Installs `simple-website-redirect.zip`
   - Sets WP options: `simple_website_redirect_url`, `simple_website_redirect_type = 301`, `simple_website_redirect_status = 1`

## Key files required

- `all-in-one-wp-migration-url-extension.zip` (same dir as script)
- `simple-website-redirect.zip` (same dir as script)
