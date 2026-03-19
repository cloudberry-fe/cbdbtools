# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CBDBTools is a suite of shell scripts and a Flask web application for automating deployment and initialization of Cloudberry/Greenplum/HashData MPP database clusters on CentOS/RHEL 7-9.

## Commands

### Command-line Deployment
```bash
# Start deployment (uses DEPLOY_TYPE from config)
sh run.sh

# Force specific deployment type
sh run.sh single   # Single-node deployment
sh run.sh multi    # Multi-node deployment
```

### Web UI Deployment
```bash
# Start the web UI (runs on port 5000)
sh start_web.sh
```

## Architecture

### Deployment Flow
```
run.sh → deploycluster.sh → init_env.sh → init_cluster.sh
                                ↓
                         init_env_segment.sh (multi-node only)
```

### Key Files

| File | Purpose |
|------|---------|
| `deploycluster_parameter.sh` | Central configuration file with all environment variables |
| `deploycluster.sh` | Main orchestration script; detects DB type, sets paths, calls init scripts |
| `init_env.sh` | Coordinator node setup: packages, system params, users, SSH, DB installation |
| `init_env_segment.sh` | Segment node setup for multi-node deployments |
| `init_cluster.sh` | Database cluster initialization using gpinitsystem |
| `segmenthosts.conf` | Host/IP configuration for multi-node clusters |
| `run.sh` | Entry point; checks for existing processes, launches deployment in background |
| `cluster_deploy_web.py` | Flask web UI for remote deployment via SSH |
| `start_web.sh` | Web UI startup: installs deps, creates venv, starts gunicorn |

### Database Type Detection
`deploycluster.sh` auto-detects database type from RPM filename and sets:
- `DB_TYPE`, `DB_VERSION`, `DB_KEYWORD`
- `CLOUDBERRY_BINARY_PATH` (e.g., `/usr/local/cloudberry-db`, `/usr/local/greenplum-db`)
- `CLUSTER_ENV` (environment script name)
- `LEGACY_VERSION` (for Greenplum < 7)

Supported databases: Cloudberry, Greenplum (5.x/6.x/7.x), HashData Lightning, SynxDB

### Multi-node Deployment Requirements
1. Configure `segmenthosts.conf` with coordinator and segment IPs/hostnames
2. Set `DEPLOY_TYPE="multi"` in `deploycluster_parameter.sh`
3. Configure segment access (`SEGMENT_ACCESS_METHOD` as `keyfile` or `password`)

### Web UI Architecture
- Flask app with paramiko for SSH connections
- Can run on any machine and deploy to remote servers
- Uploads deployment scripts via SFTP
- Real-time log streaming via Server-Sent Events
- Configuration stored in Flask session

## Configuration

### Mandatory Parameters (in `deploycluster_parameter.sh`)
- `ADMIN_USER` - OS user for cluster (default: gpadmin)
- `ADMIN_USER_PASSWORD` - Password for OS user
- `CLOUDBERRY_RPM` - Path to database RPM (must use absolute path)
- `COORDINATOR_HOSTNAME` / `COORDINATOR_IP`
- `DEPLOY_TYPE` - `single` or `multi`

### Key Optional Parameters
- `INIT_ENV_ONLY` - Set to `true` to skip cluster initialization
- `INSTALL_DB_SOFTWARE` - Set to `false` to skip RPM installation (for reinit)
- `WITH_MIRROR` / `WITH_STANDBY` - Enable mirrors/standby
- `MAUNAL_YUM_REPO` - Set to `true` to skip auto YUM repo configuration
