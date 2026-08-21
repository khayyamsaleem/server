#!/bin/sh
# Idempotent Prowlarr seeding via the API. Runs inside the (stock linuxserver)
# Prowlarr container, so it must stay interpreter-free: curl/grep/sed/tr only
# (the image has no python3/jq). Payloads live in ./prowlarr-payloads, mounted
# read-only at /configure/prowlarr-payloads. Re-running is safe: each object is
# created only when absent (matched by name), so a clean rebuild reproduces the
# current setup: FlareSolverr proxy + Radarr/Sonarr apps + indexers.
set -e

BASE="http://localhost:9696"
API_KEY="${PROWLARR_API_KEY}"
PAYLOADS="/configure/prowlarr-payloads"
TMP="/tmp/pw-seed"
mkdir -p "$TMP"

wait_ready() {
  echo "[prowlarr-init] Waiting for API..."
  i=0
  while [ "$i" -lt 30 ]; do
    if curl -sf "$BASE/api/v1/system/status" -H "X-Api-Key: $API_KEY" >/dev/null 2>&1; then
      echo "[prowlarr-init] API ready."
      return 0
    fi
    i=$((i + 1)); sleep 2
  done
  echo "[prowlarr-init] Timed out waiting for API."
  exit 1
}

# Ensure tag <label> exists; print its numeric id. (Prowlarr pretty-prints JSON,
# so matching tolerates the space after each colon.)
ensure_tag() {
  label=$1
  if ! curl -sf "$BASE/api/v1/tag" -H "X-Api-Key: $API_KEY" \
       | grep -Eq "\"label\": *\"$label\""; then
    curl -sf -X POST "$BASE/api/v1/tag" -H "X-Api-Key: $API_KEY" \
      -H "Content-Type: application/json" --data "{\"label\":\"$label\"}" >/dev/null
  fi
  curl -sf "$BASE/api/v1/tag" -H "X-Api-Key: $API_KEY" \
    | awk "/\"label\": *\"$label\"/{f=1} f&&/\"id\":/{gsub(/[^0-9]/,\"\");print;exit}"
}

# Render a payload, substituting the flaresolverr tag id (sentinel 909090) and
# the arr API keys (Prowlarr redacts these in GET, so they come from env).
render() {
  sed -e "s/909090/${TAG_ID}/g" \
      -e "s/__RADARR_API_KEY__/${RADARR_API_KEY}/g" \
      -e "s/__SONARR_API_KEY__/${SONARR_API_KEY}/g" \
      "$PAYLOADS/$1" > "$TMP/$1"
}

# seed <endpoint> <name> <payload-file> [query-string]
seed() {
  ep=$1; name=$2; file=$3; qs=$4
  if curl -sf "$BASE/api/v1/$ep" -H "X-Api-Key: $API_KEY" 2>/dev/null \
       | grep -Eq "\"name\": *\"$name\""; then
    echo "[prowlarr-init] $name already present, skipping."
    return 0
  fi
  render "$file"
  if curl -sf -X POST "$BASE/api/v1/${ep}${qs}" -H "X-Api-Key: $API_KEY" \
       -H "Content-Type: application/json" --data-binary @"$TMP/$file" >/dev/null; then
    echo "[prowlarr-init] $name seeded."
  else
    echo "[prowlarr-init] WARN: $name POST failed (retries on next start)."
  fi
}

wait_ready

TAG_ID=$(ensure_tag flaresolverr || true)
[ -n "$TAG_ID" ] || { echo "[prowlarr-init] ERROR: could not resolve flaresolverr tag id."; exit 1; }
echo "[prowlarr-init] flaresolverr tag id = ${TAG_ID}"

# FlareSolverr indexer-proxy (host flaresolverr:8191, 180s timeout, tagged flaresolverr)
seed indexerproxy "FlareSolverr" proxy-flaresolverr.json

# Applications (Radarr/Sonarr) — apiKey injected from env
seed applications "Radarr" app-radarr.json
seed applications "Sonarr" app-sonarr.json

# Indexers. forceSave=true so a flaky Cloudflare connect-test never blocks seeding;
# EZTV + Torrent Downloads + 1337x + TPB carry the flaresolverr tag (route through the proxy).
seed indexer "YTS"               indexer-yts.json              "?forceSave=true"
seed indexer "TorrentsCSV"       indexer-torrentscsv.json      "?forceSave=true"
seed indexer "EZTV"              indexer-eztv.json             "?forceSave=true"
seed indexer "Torrent Downloads" indexer-torrentdownloads.json "?forceSave=true"
seed indexer "The Pirate Bay"    indexer-tpb.json              "?forceSave=true"
seed indexer "1337x"             indexer-1337x.json            "?forceSave=true"
seed indexer "Knaben"            indexer-knaben.json           "?forceSave=true"

echo "[prowlarr-init] Done."
