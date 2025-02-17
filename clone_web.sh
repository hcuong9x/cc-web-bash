#!/bin/bash

# Check if at least one domain is provided
if [ $# -eq 0 ]; then
  echo "Usage: $0 <domain1> <domain2> ... <domainN>"
  exit 1
fi

# Loop through each domain passed as a parameter
for DOMAIN in "$@"
do
  # Run the list commands for each domain
  echo "Processing $DOMAIN..."

  site "$DOMAIN" -wp
  sudo httpauth "$DOMAIN" -wp-admin=off
  sudo site "$DOMAIN" -ssl=on

  echo "Commands executed successfully for $DOMAIN."
done
