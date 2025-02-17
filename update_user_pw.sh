#!/bin/bash

# Check if all required parameters (domain, email, password) are provided
if [ $# -ne 3 ]; then
  echo "Usage: $0 <domain> <email> <password>"
  exit 1
fi

DOMAIN="$1"
EMAIL="$2"
PASSWORD="$3"

# Run the command with the provided parameters
sudo webinoly -wp-user="$DOMAIN" -update="$EMAIL" -pass="$PASSWORD"

echo "Command executed successfully for domain: $DOMAIN with email: $EMAIL."
