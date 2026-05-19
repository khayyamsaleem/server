#!/bin/sh
# Idempotent Prowlarr application wiring: adds Radarr + Sonarr if not present.
set -e

BASE="http://localhost:9696"
API_KEY="${PROWLARR_API_KEY}"
RADARR_KEY="${RADARR_API_KEY}"
SONARR_KEY="${SONARR_API_KEY}"

wait_ready() {
  echo "[prowlarr-init] Waiting for API..."
  for i in $(seq 1 30); do
    if curl -sf "$BASE/api/v1/system/status" -H "X-Api-Key: $API_KEY" >/dev/null 2>&1; then
      echo "[prowlarr-init] API ready."
      return 0
    fi
    sleep 2
  done
  echo "[prowlarr-init] Timed out."
  exit 1
}

add_app() {
  impl=$1
  name=$2
  base_url=$3
  arr_key=$4
  sync_cats=$5

  existing=$(curl -sf "$BASE/api/v1/applications" -H "X-Api-Key: $API_KEY")
  if echo "$existing" | grep -q "\"$name\""; then
    echo "[prowlarr-init] $name already configured, skipping."
    return 0
  fi

  schema=$(curl -sf "$BASE/api/v1/applications/schema" -H "X-Api-Key: $API_KEY")
  payload=$(echo "$schema" | python3 -c "
import sys, json
schemas = json.load(sys.stdin)
s = [x for x in schemas if x['implementation'] == '$impl'][0]
s['name'] = '$name'
s['syncLevel'] = 'fullSync'
for f in s['fields']:
    if f['name'] == 'prowlarrUrl': f['value'] = 'http://prowlarr:9696'
    elif f['name'] == 'baseUrl': f['value'] = '$base_url'
    elif f['name'] == 'apiKey': f['value'] = '$arr_key'
    elif f['name'] in ('syncCategories', 'animeSyncCategories'): f['value'] = $sync_cats
print(json.dumps(s))
")
  echo "$payload" | curl -sf -X POST "$BASE/api/v1/applications" \
    -H "X-Api-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    --data-binary @- >/dev/null
  echo "[prowlarr-init] $name wired."
}

wait_ready
add_app "Radarr" "Radarr" "http://radarr:7878"  "$RADARR_KEY" "[2000,2010,2020,2030,2040,2045,2050,2060,2070,2080,2090]"
add_app "Sonarr" "Sonarr" "http://sonarr:8989"  "$SONARR_KEY" "[5000,5010,5020,5030,5040,5045,5050,5060,5070,5080,5090]"
echo "[prowlarr-init] Done."
