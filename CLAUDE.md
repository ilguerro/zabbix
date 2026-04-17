# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker Compose infrastructure for a multi-tenant Zabbix 7.0 LTS monitoring setup in an MSP (Managed Service Provider) context. Written in Italian. No application code to build, lint, or test — this is purely infrastructure-as-code (Docker Compose + environment files).

## Architecture

Two independent Docker Compose stacks designed to be deployed separately:

- **`central/`** — Central Zabbix server stack deployed at the MSP headquarters. Services: Zabbix Server, PostgreSQL 16 + TimescaleDB, Zabbix Web (nginx), Caddy reverse proxy (automatic HTTPS via Let's Encrypt), Zabbix Agent 2 (self-monitoring), SNMP trap receiver, automated PostgreSQL backup. Two Docker networks: `zabbix-backend` (internal, no external access) and `zabbix-frontend` (Caddy to web UI).

- **`proxy/`** — Lightweight proxy stack cloned and customized per client site. Services: Zabbix Proxy (active mode, SQLite), SNMP trap receiver, Zabbix Agent 2 (self-monitoring). Connects outbound to the central server on port 10051 with TLS PSK encryption.

## Key Commands

```bash
# Central stack
cd central && docker compose up -d          # Start
cd central && docker compose logs -f zabbix-server  # Watch server startup
cd central && docker compose pull && docker compose up -d  # Upgrade minor version

# Proxy stack
cd proxy && docker compose up -d
cd proxy && docker compose logs -f zabbix-proxy

# Manual DB backup
docker exec zabbix-postgres-backup /backup.sh
```

## Critical Constraints

- **Version parity**: Proxy and server MUST run the same Zabbix major/minor version (`ZABBIX_VERSION` in both `.env` files).
- **TLS PSK**: Every proxy requires a unique 256-bit PSK. The PSK identity and value must match exactly between the central frontend config and the proxy's `.env` + `enc/proxy.psk`.
- **TimescaleDB conversion**: Must be run once manually after first central stack boot (extract `timescaledb.sql` from the server container, execute against PostgreSQL).
- **PostgreSQL is never exposed externally** — only accessible on the internal `zabbix-backend` Docker network.
- **Caddy requires DNS**: The FQDN in `ZBX_FQDN` must have an A record pointing to the server, and ports 80/443 must be open for Let's Encrypt HTTP-01 challenge.
- The `.env` files contain placeholder passwords — they must be changed before production deployment.
