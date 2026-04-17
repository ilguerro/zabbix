# Zabbix Server Centrale - MSP Setup

Stack Docker Compose per il server Zabbix centrale con PostgreSQL + TimescaleDB.

## Struttura

```
central/
├── docker-compose.yml        # Stack principale
├── .env                      # Variabili d'ambiente (cambia le password!)
├── postgres/
│   └── init/
│       └── 01-enable-timescaledb.sh   # Abilita TimescaleDB al primo avvio
├── caddy/
│   └── Caddyfile             # Configurazione reverse proxy + HTTPS
├── zabbix/
│   ├── alertscripts/         # Script custom per alerting (webhook ecc.)
│   ├── externalscripts/      # Script per external checks
│   ├── mibs/                 # MIB SNMP custom (Ubiquiti, stampanti, ecc.)
│   └── enc/                  # File PSK per TLS con i proxy
└── backups/                  # Backup automatici del DB
```

## Setup iniziale

### 1. Prerequisiti DNS (per Caddy + Let's Encrypt)

Prima di avviare, assicurati che:
- Il dominio scelto (es. `zabbix.msp.example.com`) abbia un record **A** che
  punta all'IP pubblico di questo server
- Le porte **80 e 443** siano raggiungibili dall'esterno (Let's Encrypt usa
  la challenge HTTP-01 via porta 80 per emettere i certificati)
- Il firewall non blocchi queste porte in ingresso

### 2. Personalizza `.env`

Genera una password forte per PostgreSQL:

```bash
openssl rand -base64 32
```

Aggiorna `.env` con:
- `POSTGRES_PASSWORD`: password generata sopra
- `ZBX_FQDN`: il tuo dominio (es. `zabbix.msp.example.com`)
- `ACME_EMAIL`: email valida per notifiche Let's Encrypt

### 3. Crea le cartelle necessarie

```bash
mkdir -p zabbix/{alertscripts,externalscripts,mibs,enc}
mkdir -p backups
```

### 4. (Opzionale) Test con Let's Encrypt staging

Se è il primo deploy e vuoi evitare di consumare rate limit di Let's Encrypt,
decommenta la riga `acme_ca` nel `caddy/Caddyfile` per usare lo staging.
Ricordati di ricommentarla e di cancellare il volume `caddy_data` una volta
pronto per la produzione:

```bash
docker compose down
docker volume rm zabbix-central_caddy_data
# riavvia con acme_ca commentato per ottenere certificati veri
docker compose up -d
```

### 5. Avvia lo stack

```bash
docker compose up -d
```

Al primo avvio Zabbix impiega qualche minuto a creare lo schema. Controlla i log:

```bash
docker compose logs -f zabbix-server
```

Aspetta finché vedi `server #0 started`.

Caddy nel frattempo richiederà il certificato Let's Encrypt. Controlla:

```bash
docker compose logs -f caddy
```

Devi vedere messaggi tipo `certificate obtained successfully`.

### 6. Converti le tabelle in hypertables TimescaleDB

**Questo passaggio è fondamentale** per sfruttare TimescaleDB. Va fatto UNA VOLTA SOLA dopo il primo avvio:

```bash
# Estrai lo script timescaledb.sql dal container server
docker cp zabbix-server:/usr/share/doc/zabbix-server-postgresql/timescaledb.sql.gz /tmp/
gunzip /tmp/timescaledb.sql.gz
docker cp /tmp/timescaledb.sql zabbix-postgres:/tmp/

# Eseguilo sul database
docker exec -it zabbix-postgres psql -U zabbix -d zabbix -f /tmp/timescaledb.sql
```

### 7. Primo accesso

Accedi a `https://<ZBX_FQDN>` (es. `https://zabbix.msp.example.com`).

Credenziali di default:
- Utente: `Admin`
- Password: `zabbix`

**Cambia subito la password di Admin.**

### 8. Abilita la compressione da frontend

Vai in:
`Administration → General → Housekeeping → Override item history period / trend period`
e abilita la compressione. Con TimescaleDB puoi comprimere dati più vecchi di 7-14 giorni risparmiando 70-90% di spazio.

## Porte esposte

| Porta   | Servizio         | Note                                          |
|---------|------------------|-----------------------------------------------|
| 80      | Caddy HTTP       | Redirect a HTTPS + challenge Let's Encrypt    |
| 443     | Caddy HTTPS      | Frontend Zabbix con TLS automatico            |
| 443/udp | Caddy HTTP/3     | QUIC (opzionale ma consigliato)               |
| 10051   | Zabbix Server    | Per proxy e agent attivi                      |
| 162     | SNMP Traps       | Per ricevere trap da switch/stampanti         |

Il container `zabbix-web` NON espone porte pubblicamente: è raggiungibile
solo attraverso Caddy sulla network interna `zabbix-frontend`.

## Sicurezza

- [x] HTTPS automatico con Let's Encrypt via Caddy
- [x] Redirect automatico HTTP → HTTPS
- [x] Header di sicurezza (HSTS, X-Frame-Options, ecc.) impostati in Caddy
- [ ] Considera di limitare l'accesso al frontend via IP (solo VPN MSP) -
      vedi esempio commentato nel `Caddyfile`
- [ ] Limita l'accesso alla 10051 solo agli IP dei tuoi proxy (firewall host)
- [x] Abilita TLS PSK per ogni proxy (vedi sezione dedicata)
- [x] Cambia subito la password dell'utente `Admin` di Zabbix

## Generazione PSK per i proxy

Per ogni proxy genera una PSK univoca:

```bash
openssl rand -hex 32 > zabbix/enc/proxy-CLIENTE-NOME.psk
chmod 600 zabbix/enc/proxy-CLIENTE-NOME.psk
```

Poi nel frontend Zabbix crea il proxy (Administration → Proxies → Create proxy)
con il nome hostname del proxy, e in "Encryption" imposta PSK con:
- **PSK identity**: `PSK-CLIENTE-NOME` (stringa libera, deve corrispondere al proxy)
- **PSK**: contenuto del file `.psk`

Lo stesso valore va nel `.env` del proxy.

## Manutenzione

### Backup manuale immediato
```bash
docker exec zabbix-postgres-backup /backup.sh
```

### Verifica stato backup
```bash
ls -lh backups/daily/
```

### Aggiornamento minor version (es. 7.0.5 → 7.0.6)
```bash
docker compose pull
docker compose up -d
```

Gli upgrade major (es. 7.0 → 7.2) richiedono procedura specifica: leggi le
release notes di Zabbix e fai sempre backup prima.

### Verifica compressione TimescaleDB
```bash
docker exec -it zabbix-postgres psql -U zabbix -d zabbix -c \
  "SELECT hypertable_name, compression_enabled FROM timescaledb_information.hypertables;"
```

### Gestione Caddy

**Reload configurazione senza downtime** (dopo modifiche al Caddyfile):
```bash
docker exec zabbix-caddy caddy reload --config /etc/caddy/Caddyfile
```

**Verifica validità Caddyfile prima di applicare**:
```bash
docker exec zabbix-caddy caddy validate --config /etc/caddy/Caddyfile
```

**Ispeziona certificati Let's Encrypt**:
```bash
docker exec zabbix-caddy ls -la /data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/
```

**Log Caddy in tempo reale**:
```bash
docker compose logs -f caddy
```

**Backup certificati** (vengono già salvati nel volume `caddy_data` ma
puoi esportarli):
```bash
docker run --rm -v zabbix-central_caddy_data:/data -v $(pwd):/backup \
  alpine tar czf /backup/caddy_data_backup.tar.gz -C /data .
```
