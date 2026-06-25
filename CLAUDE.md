# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Bash scripts for managing WordPress sites on Ubuntu 24.04 servers running the Webinoly stack (Nginx + PHP-FPM 8.4 + MariaDB). All scripts assume Webinoly is installed and sites live at `/var/www/<domain>/htdocs`.

## Rules

Detailed guidance is in `.claude/rules/`:

| Rule file | Scope |
|---|---|
| `stack-and-conventions.md` | Always loaded — server stack, site paths, WP-CLI pattern, permissions, bundled zips |
| `clone-template.md` | `clone-template.sh` — invocation, prerequisites, restore workflow, multi-domain |
| `301-redirect.md` | `301_website.sh` — domain migration + 301 redirect setup |
| `server-optimization.md` | `optimize-*.sh` — PHP-FPM/MariaDB/Nginx tuning, safety patterns |
| `utility-scripts.md` | Other scripts — site creation, plugin cleanup, WP-CLI, Zabbix, user management |
