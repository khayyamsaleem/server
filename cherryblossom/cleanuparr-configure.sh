#!/bin/sh
# Idempotent Cleanuparr seeder. Runs as init container after Cleanuparr is
# healthy: claims the admin account (the setup endpoints are unauthenticated
# until an account exists, so this must happen right away), then converges
# download client, *arr instances, Malware Blocker, and Queue Cleaner config
# through the API. Settings not named here keep whatever the UI set.
set -eu

apk add --no-cache curl jq >/dev/null

C=http://cleanuparr:11011
TRANSMISSION_HOST=http://gluetun:9091

log() { echo "[cleanuparr-init] $*"; }

api() { # api METHOD PATH [JSON]
  if [ $# -ge 3 ]; then
    curl -sf -X "$1" -H "X-Api-Key: $KEY" -H 'Content-Type: application/json' "$C/api/$2" -d "$3"
  else
    curl -sf -X "$1" -H "X-Api-Key: $KEY" "$C/api/$2"
  fi
}

# --- account ---------------------------------------------------------------
creds=$(jq -nc --arg u "$CLEANUPARR_USERNAME" --arg p "$CLEANUPARR_PASSWORD" '{username:$u,password:$p}')
if [ "$(curl -sf $C/api/auth/status | jq -r .setupCompleted)" != true ]; then
  log "Creating admin account $CLEANUPARR_USERNAME"
  curl -s -X POST $C/api/auth/setup/account -H 'Content-Type: application/json' -d "$creds" >/dev/null
  curl -sf -X POST $C/api/auth/setup/complete >/dev/null
fi
TOKEN=$(curl -sf -X POST $C/api/auth/login -H 'Content-Type: application/json' -d "$creds" | jq -r .tokens.accessToken)
KEY=$(curl -sf -H "Authorization: Bearer $TOKEN" $C/api/account/api-key | jq -r .apiKey)

# --- login bypass ----------------------------------------------------------
# The account above exists so the anonymous setup endpoints can't be claimed
# by anyone else; day to day, skip the login for the compose network (and the
# host, which reaches it via the bridge gateway). Not on the tailnet, so that
# is local-only access -- same trust level as the *arrs.
api GET configuration/general | jq -c '
  .auth.disableAuthForLocalAddresses = true
  | .auth.trustedNetworks = ["172.17.0.0/16"]' \
  | { read -r body; api PUT configuration/general "$body" >/dev/null; }
log "Auth: login bypassed for 172.17.0.0/16"

# --- download client -------------------------------------------------------
# Transmission shares gluetun's netns; RPC has no auth (same as Sonarr's view).
client=$(jq -nc --arg h "$TRANSMISSION_HOST" '{
  enabled:true, name:"Transmission", typeName:"Transmission", type:"Torrent",
  host:$h, urlBase:"/transmission/", username:"", password:""}')
id=$(api GET configuration/download_client | jq -r '.clients[] | select(.name=="Transmission") | .id')
if [ -n "$id" ]; then
  api PUT "configuration/download_client/$id" "$client" >/dev/null
else
  api POST configuration/download_client "$client" >/dev/null
fi
log "Download client: Transmission @ $TRANSMISSION_HOST"

# --- *arr instances ---------------------------------------------------------
upsert_arr() { # upsert_arr sonarr http://sonarr:8989 KEY VERSION
  body=$(jq -nc --arg n "$1" --arg u "$2" --arg k "$3" --argjson v "$4" \
    '{enabled:true, name:$n, url:$u, apiKey:$k, version:$v}')
  id=$(api GET "configuration/$1" | jq -r --arg n "$1" '.instances[] | select(.name==$n) | .id')
  if [ -n "$id" ]; then
    api PUT "configuration/$1/instances/$id" "$body" >/dev/null
  else
    api POST "configuration/$1/instances" "$body" >/dev/null
  fi
  log "Instance: $1 @ $2"
}
upsert_arr sonarr http://sonarr:8989 "$SONARR_API_KEY" 4
upsert_arr radarr http://radarr:7878 "$RADARR_API_KEY" 6

# --- Malware Blocker --------------------------------------------------------
# Community blocklist (.exe, .lnk, .scr, ... ~850 patterns). Checks every 5
# minutes; the shipped default cron "0/5 * * * * ?" is every 5 *seconds*.
# deleteIfAnyFileBlocked MUST stay false: the list also blocks *.nfo and
# *.txt, which nearly every real release carries (RARBG.txt, group .nfo).
# Turning it on removed 41 legit in-flight downloads on first run. With it
# off, blocked extras are just unselected, and a torrent is only removed when
# every file is blocked -- which is exactly the lone-.exe fakes.
BLOCKLIST=https://cleanuparr.pages.dev/static/blacklist
api GET configuration/malware_blocker | jq -c --arg b "$BLOCKLIST" '
  .enabled = true
  | .cronExpression = "0 0/5 * * * ?"
  | .useAdvancedScheduling = false
  | .deleteIfAnyFileBlocked = false
  | .sonarr = {enabled:true, blocklistType:"Blacklist", blocklistPath:$b}
  | .radarr = {enabled:true, blocklistType:"Blacklist", blocklistPath:$b}' \
  | { read -r body; api PUT configuration/malware_blocker "$body" >/dev/null; }
log "Malware Blocker: enabled (sonarr, radarr)"

# --- Queue Cleaner ----------------------------------------------------------
# Only strike failed imports that are unambiguously junk; anything else (title
# mismatch, not an upgrade, ...) stays for a human to look at.
api GET configuration/queue_cleaner | jq -c '
  .enabled = true
  | .cronExpression = "0 0/5 * * * ?"
  | .useAdvancedScheduling = false
  | .failedImport.maxStrikes = 3
  | .failedImport.patternMode = "Include"
  | .failedImport.patterns = [
      "Found executable file",
      "Found potentially dangerous file",
      "No files found are eligible for import"]' \
  | { read -r body; api PUT configuration/queue_cleaner "$body" >/dev/null; }
log "Queue Cleaner: enabled (failed imports, 3 strikes)"

log "Done."
