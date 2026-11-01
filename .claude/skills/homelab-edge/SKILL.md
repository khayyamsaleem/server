---
name: homelab-edge
description: Manage how this homelab's services are reached — tailnet-only Tailscale Services (svc:*), public *.k5m.sh routes through juul's Traefik behind Cloudflare, Cloudflare DNS/Access, and the Tailscale policy. Use when adding, moving, renaming or removing a service's address, exposing something publicly or tailnet-only, changing DNS records or Access apps, or debugging "can't reach X" on k5m.sh / mango-hawksbill.ts.net.
---

# Homelab edge: Tailscale + Cloudflare

## Topology (verify live before acting; this drifts)
- **Tailnet:** `mango-hawksbill.ts.net`. Two tagged (`tag:infra-overlay`) Docker sidecars serve containers to the tailnet:
  - `cherryblossom-docker`: `cherryblossom/tailscale-serve.json`, service `tailscale` in `cherryblossom/docker-compose.infra.yml`
  - `juul-docker`: `juul/tailscale-serve.json`, service `tailscale` in `juul/docker-compose.networking.yml`. Traefik (`proxy`) shares its netns.
- **Tailnet-only apps** are Tailscale Services (`Services` block in serve.json), one HTTPS name each: `svc:hermes`, `svc:code`, `svc:forge`, `svc:torrent` (cherryblossom); `svc:grafana`, `svc:traefik` (juul). Each one is `https://<name>.mango-hawksbill.ts.net`.
- **Public apps:** Cloudflare (proxied DNS) → juul Traefik (`juul/dynamic/*.yml`, plus docker labels) → `cherryblossom-docker:<port>` TCP forwards on the tailnet. The https entrypoint only admits Cloudflare and private ranges (`juul/dynamic/cloudflare-only.yml`). Every public app must have **its own login**. Cloudflare Access is no longer used for them.
- **Deploys:** pushing to `master` makes Jenkins (on juul) run `git reset --hard origin/master` and `docker compose up -d` on both hosts. Merge = deploy.

## Rules
- Anything that can execute code or administer the host (OpenCode, Forge, Grafana, Traefik dashboard, Jupyter, Hermes) stays **tailnet-only**. Don't give it a public route.
- Never put tokens in the repo (it's PUBLIC) or in PR text. Credentials:
  - Tailscale: an OAuth client in `~/.config/homelab/tailscale.env` (`TS_OAUTH_CLIENT_ID`, `TS_OAUTH_CLIENT_SECRET`) with scopes `services`, `policy_file`, `devices:core:read`. Mint a short-lived token:
    `curl -s -d "client_id=$TS_OAUTH_CLIENT_ID" -d "client_secret=$TS_OAUTH_CLIENT_SECRET" https://api.tailscale.com/api/v2/oauth/token | jq -r .access_token`
    If the file is missing, ask the user. Don't hunt for credentials.
  - Cloudflare: use the `cloudflare` MCP server from the official plugin (OAuth). Run `/mcp` to authorize if needed. The CLI fallback is the API with a token the user provides for that session.
- DNS/Access deletions and policy edits are outward-facing. Confirm with the user unless they already said to.

## Add a tailnet-only app
1. Pick a name and a backend reachable from the sidecar's network (a container name and port).
2. Add it to the sidecar's serve.json:
   ```json
   "svc:NAME": {"TCP": {"443": {"HTTPS": true}},
     "Web": {"NAME.mango-hawksbill.ts.net:443": {"Handlers": {"/": {"Proxy": "http://BACKEND:PORT"}}}}}
   ```
3. Define it: `PUT https://api.tailscale.com/api/v2/tailnet/-/vip-services/svc:NAME` with body `{"name":"svc:NAME","ports":["tcp:443"],"comment":"..."}`.
4. Policy: add `"svc:NAME": ["tag:infra-overlay"]` to `autoApprovers.services`. GET the policy with `Accept: application/hujson`, `POST .../acl/validate`, then POST with `If-Match: <etag>`.
5. Merge, then **force-recreate the sidecar**. serve.json is a single-file bind mount, so `git reset` and editors replace the inode and the container keeps reading the stale file. On juul, recreate `tailscale` and `proxy` together, because they share a netns.
6. Verify: `GET .../vip-services/svc:NAME/devices` shows `approved:auto` / `ready`, and `curl https://NAME.mango-hawksbill.ts.net/` works.
7. If the app builds absolute URLs (e.g. Grafana `GF_SERVER_ROOT_URL`), set them to the new name.

## Add a public app (must have its own auth)
1. Add a TCP forward on the cherryblossom sidecar if the backend lives there, e.g. `"PORT": {"TCPForward": "container:PORT"}`.
2. Add a Traefik route in `juul/dynamic/NAME.yml` with `Host(\`NAME.k5m.sh\`)` pointing at `http://cherryblossom-docker:PORT`.
3. Cloudflare DNS: a proxied record for `NAME.k5m.sh` to juul's origin (copy an existing record's target).
4. Verify through Cloudflare. Direct-to-origin requests must get 403.

## Remove or move an app
Reverse the steps: delete the serve.json entry or route, the DNS record and the vip-service. Check `rg` for leftover references (prometheus.yml, dynamic/, compose labels).

## Gotchas
- Renaming the tailnet: containers keep the old DNS search domain until they're restarted. Restart juul `tailscale`+`proxy` and Jenkins, otherwise short names like `cherryblossom-docker` fail (502s, failed deploys).
- Host MagicDNS on cherryblossom needs NetworkManager `rc-manager=resolvconf` (openresolv mode). See the memory note.
- `tailscale service list` (client ≥1.102) shows the Services this node can see. The macOS app lists Services in its app window (≥1.104).
