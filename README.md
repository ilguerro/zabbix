# Zabbix MSP - Infrastruttura di monitoraggio

Setup Docker Compose per monitoraggio multi-tenant in ambiente MSP.

## Architettura

```
┌─────────────────────────────────────────────────────────────────────┐
│                       SEDE MSP (Server Centrale)                    │
│                                                                     │
│   ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │
│   │  Zabbix Server  │  │  PostgreSQL +   │  │  Zabbix Web     │     │
│   │                 │──│  TimescaleDB    │──│  (nginx)        │     │
│   └─────────────────┘  └─────────────────┘  └─────────────────┘     │
│          │ 10051 (TLS PSK)                                          │
└──────────┼──────────────────────────────────────────────────────────┘
           │
           │ VPN o Internet con TLS PSK
           │
    ┌──────┴───────┬────────────────┬────────────────┐
    │              │                │                │
┌───▼────────┐ ┌───▼────────┐ ┌───▼────────┐ ┌───▼────────┐
│ Proxy      │ │ Proxy      │ │ Proxy      │ │ Proxy      │
│ Cliente A  │ │ Cliente B  │ │ Cliente C  │ │ Cliente D  │
│ (SQLite)   │ │ (SQLite)   │ │ (SQLite)   │ │ (SQLite)   │
└─────┬──────┘ └─────┬──────┘ └─────┬──────┘ └─────┬──────┘
      │              │              │              │
      │ monitoring   │              │              │
      │              │              │              │
   ┌──▼──────────────▼──────────────▼──────────────▼──┐
   │  Target: Proxmox, Win/Lin server, switch, stampanti  │
   └──────────────────────────────────────────────────────┘
```

## Struttura repository

```
zabbix-msp/
├── central/         # Da installare sul server centrale MSP
│   ├── docker-compose.yml
│   ├── .env
│   ├── postgres/init/    # Script init TimescaleDB
│   └── README.md
└── proxy/           # Da clonare/personalizzare per ogni sede cliente
    ├── docker-compose.yml
    ├── .env
    └── README.md
```

## Ordine di deploy

1. **Server centrale** (`central/`): setup completo, conversione TimescaleDB,
   primo login e cambio password Admin
2. **Per ogni cliente**:
   a. Crea proxy nel frontend Zabbix con PSK
   b. Deploy `proxy/` sulla VM in sede cliente
   c. Verifica connessione
   d. Crea host group `Cliente-NOME`, user group dedicato se serve
   e. Assegna host monitorati al proxy

## Versioni

Entrambi gli stack usano **Zabbix 7.0 LTS**. Mantieni sempre versioni
allineate tra server e proxy.

## Sicurezza - riassunto

- [x] TLS PSK obbligatorio per ogni proxy
- [x] PSK univoca per cliente (256 bit)
- [x] PostgreSQL non esposto esternamente (solo network interno Docker)
- [x] Frontend da mettere dietro reverse proxy con HTTPS
- [x] Password Admin Zabbix cambiata al primo accesso
- [x] Backup PostgreSQL automatico giornaliero con retention

## Performance attese

Con la configurazione default:
- Server centrale: gestisce 1000+ host, 10k+ item, 500 NVPS senza problemi
  su una VM da 4 vCPU / 8 GB RAM
- Proxy cliente: gestisce 50-100 host (tipica sede piccola/media) con
  2 vCPU / 2 GB RAM

Per volumi più grandi, aumenta cache, pollers e RAM. Consulta la
documentazione Zabbix per tuning avanzato.

## Link utili

- [Documentazione ufficiale Zabbix 7.0](https://www.zabbix.com/documentation/7.0/)
- [Docker Hub Zabbix](https://hub.docker.com/u/zabbix)
- [TimescaleDB + Zabbix](https://www.zabbix.com/documentation/7.0/en/manual/appendix/install/timescaledb)
- [Template community Ubiquiti](https://github.com/zabbix/community-templates)
