# hashi-resume

A self-contained Docker-based resume renderer that populates Consul KV with resume data and renders a formatted resume using Consul Template.

## Overview

```
┌──────────────┐     ┌──────────────────┐     ┌─────────────┐     ┌──────────────┐
│  PDF Resume   │ ──▶ │ generate_fixtures │ ──▶ │ fixtures.sh │ ──▶ │ Consul KV     │
│ (.pdf)        │     │  .py (pypdf)      │     │ (consul cmd) │     │ (key/value)   │
└──────────────┘     └──────────────────┘     └─────────────┘     └──────┬───────┘
                                                                           │
                                                                           ▼
                                                                     ┌────────────┐
                                                                     │ consul-    │
                                                                     │ template   │
                                                                     │ .ctmpl      │
                                                                     └─────┬──────┘
                                                                           │
                                                                           ▼
                                                                     ┌────────────┐
                                                                     │ resume.txt │
                                                                     │ (rendered) │
                                                                     └────────────┘
```

## Prerequisites

- **Docker** (Docker Desktop or Docker Engine)
- **python3** + **pypdf** (only needed if regenerating `fixtures.sh` from PDF)

## Quick Start

```bash
# 1. Build the Docker image (only needed when fixtures.sh or Dockerfile changes)
./build.sh

# 2. Run the container and render the resume
./run.sh ASHLEY_WILLIAMS
```

The rendered resume prints to your terminal, and Consul's web UI opens at `http://localhost:8500/ui/dc1/kv`.

## Project Structure

| File | Description |
|------|-------------|
| `Dockerfile` | Multi-stage build: Alpine `builder` stage downloads HashiCorp binaries; Alpine runtime stage assembles final image |
| `build.sh` | Wrapper: `docker build -t hashi-resume:latest .` |
| `run.sh` | Starts the container, loads fixtures, renders resume via `consul-template` |
| `docker-entrypoint.sh` | Starts Consul in dev mode (`-dev -server -ui`) |
| `fixtures.sh` | Shell script with `consul kv put` commands for all resume data |
| `generate_fixtures.py` | Parses PDF resume → generates `fixtures.sh` (uses `pypdf`) |
| `resume.ctmpl` | Consul Template that renders the KV data into formatted text |
| `fixtures-original.sh` | Backup of original placeholder fixtures |

## Regenerating Fixtures from PDF

If the resume PDF changes, regenerate `fixtures.sh`:

```bash
pip3 install pypdf
python3 generate_fixtures.py
./build.sh   # rebuild image with new fixtures
```

The script accepts optional flags:
```bash
python3 generate_fixtures.py --pdf /path/to/resume.pdf --output fixtures.sh
```

## Data Mapping

The PDF resume is parsed and mapped to Consul KV keys:

| Resume Section | Consul KV Key |
|---------------|---------------|
| Address | `$1/address` |
| Email | `$1/email` |
| Phone | `$1/phone` |
| Profile Summary | `$1/profile_summary` |
| Company (with location/dates) | `$1/org/<N>/name` |
| Position Title | `$1/org/<N>/position/<P>/name` |
| Task Bullet | `$1/org/<N>/position/<P>/tasks/<T>` |

Where `$1` is the key prefix (e.g., `ASHLEY_WILLIAMS`).

## Architecture

### Docker Build (two-stage, both Alpine-based)

1. **Builder stage** (`FROM alpine:latest AS builder`): Installs `wget` + `unzip`, downloads Consul 1.6.2, Vault 1.2.3, Consul Template 0.22.0, and EnvConsul 0.9.2 binaries to `/usr/local/bin/`.

2. **Runtime stage** (`FROM alpine:latest`): Copies binaries from builder, creates non-root user, copies project files (`fixtures.sh`, `resume.ctmpl`, `docker-entrypoint.sh`), sets permissions.

### Runtime Flow

1. `docker run` starts container with `FULL_NAME` env var
2. `docker-entrypoint.sh` starts Consul agent in dev mode on port 8500
3. `run.sh` sources `fixtures.sh` → populates Consul KV store
4. `consul-template` renders `resume.ctmpl` → `resume.txt` using KV data
5. `run.sh` prints `resume.txt` and opens Consul UI

## Usage Notes

- Use underscores in the key prefix (e.g., `ASHLEY_WILLIAMS`); the template converts `_` → space for display
- The container is ephemeral (`--rm`); all data is in-memory (Consul dev mode)
- To clear cached data and start fresh: `docker stop hashi-resume && docker rm hashi-resume`
- Re-running `./run.sh` with the same name will detect existing KV data and skip re-loading fixtures
