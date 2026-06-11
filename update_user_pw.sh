#!/bin/bash

set -Eeuo pipefail

STORE_INPUT="${1:-}"
USERNAME="${2:-}"
PASSWORD="${3:-}"
INTERACTIVE=false

if [[ $# -lt 3 ]]; then
  INTERACTIVE=true
  echo "Input suggestions:"
  echo "  Store    : dragonballzstore.eu or https://dragonballzstore.eu"
  echo "  Username : WordPress login name, for example chicken"
  echo "  Password : Use at least 12 characters with uppercase, lowercase,"
  echo "             numbers, and special characters."
  echo
fi

if [[ -z "$STORE_INPUT" ]]; then
  read -r -p "Store domain or URL: " STORE_INPUT
fi

if [[ -z "$USERNAME" ]]; then
  read -r -p "WordPress username: " USERNAME
fi

if [[ -z "$PASSWORD" ]]; then
  read -r -s -p "New password: " PASSWORD
  echo
fi

DOMAIN="${STORE_INPUT#*://}"
DOMAIN="${DOMAIN%%/*}"
DOMAIN="${DOMAIN%%\?*}"
DOMAIN="${DOMAIN%%\#*}"
DOMAIN="${DOMAIN,,}"

if [[ ! "$DOMAIN" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]; then
  echo "Error: Invalid store domain: $STORE_INPUT" >&2
  exit 1
fi

if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
  echo "Error: Username and password cannot be empty." >&2
  exit 1
fi

SITE_PATH="/var/www/$DOMAIN/htdocs"

if [[ ! -d "$SITE_PATH" ]]; then
  echo "Error: Store directory not found: $SITE_PATH" >&2
  exit 1
fi

if [[ "$INTERACTIVE" == true ]]; then
  echo
  echo "Store path : $SITE_PATH"
  echo "Username   : $USERNAME"
  read -r -p "Continue updating the password? [y/N]: " CONFIRM

  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Password update cancelled."
    exit 0
  fi
fi

cd -- "$SITE_PATH"
wp user update "$USERNAME" --user_pass="$PASSWORD" --allow-root

echo "Password updated successfully for '$USERNAME' on '$DOMAIN'."
