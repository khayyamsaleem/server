# server

Docker Compose configurations for two homelab nodes connected via [Tailscale](https://tailscale.com/).

## Nodes

### juul

DigitalOcean VPS (Ubuntu). Public-facing edge and centralized monitoring hub.

**Stacks:**
- **networking** — Tailscale, Traefik (reverse proxy + Let's Encrypt via Cloudflare DNS), Watchtower
- **ci** — Jenkins, OTel Collector (pushes Jenkins metrics to VictoriaMetrics via OTLP)
- **monitoring** — VictoriaMetrics, Grafana, node-exporter, cAdvisor
- **logging** — Loki, Promtail

**Exposed services:**
| Domain | Backend |
|---|---|
| `p.k5m.sh` | Traefik dashboard |
| `ci.k5m.sh` | Jenkins |
| `g.k5m.sh` | Grafana |
| `jf.k5m.sh` | Jellyfin (on cherryblossom) |
| `t.k5m.sh` | Transmission (on cherryblossom) |
| `gpu.k5m.sh` | Open WebUI (on cherryblossom) |

### cherryblossom

On-prem server (Arch Linux) with NVIDIA GPU and attached storage.

**Stacks:**
- **media** — Jellyfin, jellyfin-exporter
- **torrenting** — Gluetun (NordVPN WireGuard), Transmission (Flood UI)
- **ai** — Ollama (GPU), PicoClaw gateway, Open WebUI, Envoy (Ollama metrics proxy)
- **monitoring** — node-exporter, cAdvisor, Promtail (ships logs to Loki on juul)
- **infra** — Watchtower

## Setup

### Prerequisites

- Docker and Docker Compose v2
- Tailscale installed and authenticated on both nodes
- NVIDIA Container Toolkit on cherryblossom (for GPU access)

### Deployment

Each node has its own directory. From the node's directory:

```bash
# Copy and fill in the env file
cp .env.sample .env
vi .env

# Start all services
docker compose up -d
```

**juul** additionally requires `jul-jsonformatter.jar` in the directory (Jenkins JSON log formatter; not committed).

**cherryblossom** additionally requires:
- PicoClaw source at `/home/khayyam/dev/pico-claw` (built locally)
- Jellyfin media drive mounted at `/mnt/jellydrive-01`

### Architecture

```
                     Internet
                        |
                        v
              +----- juul (VPS) -----+
              |                      |
              |  Traefik <-- TLS     |
              |    |                 |
              |    +-- Jenkins       |
              |    +-- Grafana       |
              |    +-- jelly --------+-------+
              |    +-- transmission -+-------+
              |                      |       |
              |  VictoriaMetrics     |       | Tailscale
              |    ^  ^              |       |
              |    |  +- OTel        |       |
              |    |    Collector    |       |
              |  Loki                |       |
              |    ^                 |       |
              +----+-----------------+       |
                   |                         |
              +----+--- cherryblossom ---+---+
              |    |                     |   |
              |  Promtail    Jellyfin <--+   |
              |                              |
              |  Gluetun (NordVPN)           |
              |    +-- Transmission          |
              |                              |
              |  Ollama (GPU)                |
              |    +-- Envoy proxy           |
              |    +-- PicoClaw              |
              |    +-- Open WebUI            |
              |                              |
              |  node-exporter, cAdvisor     |
              +------------------------------+
```
