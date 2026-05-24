---
name: docker-host-inspect
description: Inspect Docker containers running on the host machine via the mounted Docker socket. Use when the user asks about running containers, container logs, container status, or "what's running on the server".
compatibility: opencode
---

## Setup

This container has the host's Docker socket mounted at `/var/run/docker.sock`
(read-only). The `docker` CLI is installed. **You are talking to the *host*
Docker daemon, not a docker-in-docker.**

## Common queries

```bash
# What's running?
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

# Detailed state of a container
docker inspect <name-or-id>

# Recent logs
docker logs --since 5m --tail 100 <name-or-id>

# Resource usage (use --no-stream so it returns)
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Find a container by partial name
docker ps --filter "name=<substring>" --format "{{.Names}}"

# Show port mappings
docker port <name-or-id>
```

## What you CAN do (read-only socket)

- `docker ps`, `docker logs`, `docker inspect`, `docker stats`, `docker events`,
  `docker top`, `docker port`, `docker network ls`, `docker volume ls`,
  `docker exec` (yes — exec works through the socket even though it's :ro mounted,
  the :ro is on the socket file not on what the daemon can do).

## What you should NOT do without asking

- `docker run` / `docker rm` / `docker stop` / `docker restart` — these modify host
  state. Ask the user first.
- Anything that mutates volumes or networks.

## Compose files on the host

The user's compose files live under `/workspace/cherryblossom/`. The active AI
stack is `docker-compose.ai.yml`. You can `cat` these from the agent's filesystem
because /workspace is bind-mounted from the host home directory.

```bash
ls /workspace/cherryblossom/*.yml
```
