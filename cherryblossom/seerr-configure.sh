#!/bin/sh
# Idempotent Seerr settings.json seeder.
# Runs as init container (completes_successfully) before Seerr starts.
# Writes settings.json only if Jellyfin ip is not already configured.

CONFIG=/app/config/settings.json

if [ -f "$CONFIG" ]; then
  ip=$(grep -o '"ip":"[^"]*"' "$CONFIG" | grep -v '""' | head -1)
  if [ -n "$ip" ]; then
    echo "[seerr-init] Already configured (jellyfin.ip=$ip). Skipping."
    exit 0
  fi
fi

echo "[seerr-init] Writing settings.json..."
mkdir -p /app/config/logs /app/config/db
chown -R 1000:1000 /app/config

sed \
  -e "s|\${JELLYFIN_EXPORTER_TOKEN}|${JELLYFIN_EXPORTER_TOKEN}|g" \
  -e "s|\${JELLYFIN_SERVER_ID}|${JELLYFIN_SERVER_ID}|g" \
  -e "s|\${RADARR_API_KEY}|${RADARR_API_KEY}|g" \
  -e "s|\${SONARR_API_KEY}|${SONARR_API_KEY}|g" \
  /app/template/seerr-settings.json > "$CONFIG"

chown 1000:1000 "$CONFIG"
echo "[seerr-init] Done."
