#!/bin/sh
# entrypoint.sh — substitute SMTP secrets into alertmanager config at container start
# Reads SMTP_USERNAME and SMTP_PASSWORD from env (injected via env_file in compose)
# Never stores credentials in the config file or git

set -e

CONFIG_SRC="/etc/alertmanager/alertmanager.yml"
CONFIG_OUT="/tmp/alertmanager-resolved.yml"

sed \
  -e "s|SMTP_FROM_PLACEHOLDER|${SMTP_FROM_EMAIL}|g" \
  -e "s|SMTP_USER_PLACEHOLDER|${SMTP_USERNAME}|g" \
  -e "s|SMTP_PASS_PLACEHOLDER|${SMTP_PASSWORD}|g" \
  "$CONFIG_SRC" > "$CONFIG_OUT"

exec /bin/alertmanager \
  --config.file="$CONFIG_OUT" \
  --storage.path=/alertmanager \
  "$@"
