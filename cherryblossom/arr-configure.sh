#!/bin/sh
# Idempotent post-start configuration for Radarr/Sonarr.
# Runs from docker-compose entrypoint after the service is up.
# Safe to re-run: checks existing config before posting.

set -e

SERVICE=$1   # "radarr" or "sonarr"
PORT=$2      # 7878 or 8989
API_KEY=$3
CATEGORY=$4  # "movies" or "shows"
ROOT_DIR=$5  # /media/movies or /media/shows

BASE="http://localhost:$PORT"

wait_ready() {
  echo "[$SERVICE] Waiting for API..."
  for i in $(seq 1 30); do
    if wget -qO- "$BASE/api/v3/system/status" --header "X-Api-Key: $API_KEY" >/dev/null 2>&1; then
      echo "[$SERVICE] API ready."
      return 0
    fi
    sleep 2
  done
  echo "[$SERVICE] Timed out waiting for API."
  exit 1
}

configure_download_client() {
  existing=$(wget -qO- "$BASE/api/v3/downloadclient" --header "X-Api-Key: $API_KEY" 2>/dev/null)
  count=$(echo "$existing" | grep -c '"name"' 2>/dev/null || echo 0)
  if [ "$count" -gt 0 ]; then
    echo "[$SERVICE] Download client already configured, skipping."
    return 0
  fi

  schema=$(wget -qO- "$BASE/api/v3/downloadclient/schema" --header "X-Api-Key: $API_KEY")
  # Use jq to build payload from schema
  payload=$(echo "$schema" | jq --arg cat "$CATEGORY" '
    [.[] | select(.implementation == "Transmission")][0]
    | .enable = true
    | .name = "Transmission"
    | .fields = (.fields | map(
        if .name == "host" then .value = "gluetun"
        elif .name == "port" then .value = 9091
        elif .name == "username" then .value = "admin"
        elif .name == "password" then .value = "Juul1206!"
        elif .name == "movieCategory" or .name == "tvCategory" then .value = $cat
        else . end
      ))
  ')
  wget -qO- --method=POST \
    --header "X-Api-Key: $API_KEY" \
    --header "Content-Type: application/json" \
    --body-data "$payload" \
    "$BASE/api/v3/downloadclient" >/dev/null
  echo "[$SERVICE] Transmission download client configured."
}

configure_root_folder() {
  existing=$(wget -qO- "$BASE/api/v3/rootfolder" --header "X-Api-Key: $API_KEY" 2>/dev/null)
  count=$(echo "$existing" | grep -c '"path"' 2>/dev/null || echo 0)
  if [ "$count" -gt 0 ]; then
    echo "[$SERVICE] Root folder already configured, skipping."
    return 0
  fi

  wget -qO- --method=POST \
    --header "X-Api-Key: $API_KEY" \
    --header "Content-Type: application/json" \
    --body-data "{\"path\": \"$ROOT_DIR\"}" \
    "$BASE/api/v3/rootfolder" >/dev/null
  echo "[$SERVICE] Root folder $ROOT_DIR configured."
}

wait_ready
configure_download_client
configure_root_folder
echo "[$SERVICE] Configuration complete."
