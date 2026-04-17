# Zabbix Proxy - Sede Cliente

Stack Docker Compose da installare in ogni sede cliente.

## Prerequisiti

- Docker + Docker Compose
- VM con 2 vCPU, 2-4 GB RAM, 20 GB disco (sizing minimo)
- Connettività OUTBOUND verso il server centrale sulla porta 10051/TCP
- (Opzionale) Porta UDP 162 raggiungibile dagli switch/stampanti per SNMP traps

## Struttura

```
proxy/
├── docker-compose.yml
├── .env                 # Personalizzare per ogni sede!
├── enc/
│   └── proxy.psk        # File PSK (generato al setup)
├── mibs/                # MIB custom (Ubiquiti, stampanti, ecc.)
└── externalscripts/     # Script custom (opzionale)
```

## Setup

### 1. Preparazione

```bash
mkdir -p enc mibs externalscripts
chmod 700 enc
```

### 2. Configurazione server centrale (FARLO PRIMA)

Sul server centrale, genera una PSK univoca per questa sede:

```bash
openssl rand -hex 32
```

Poi nel frontend Zabbix:

1. Vai in **Administration → Proxies → Create proxy**
2. Inserisci:
   - **Proxy name**: `proxy-cliente-acme` (deve matchare `ZBX_PROXY_HOSTNAME` nel `.env`)
   - **Proxy mode**: `Active`
3. Tab **Encryption**:
   - **Connections to proxy**: PSK
   - **Connections from proxy**: PSK
   - **PSK identity**: `PSK-cliente-acme` (deve matchare `ZBX_TLS_PSK_IDENTITY` nel `.env`)
   - **PSK**: incolla il valore generato con `openssl rand -hex 32`
4. Salva

### 3. Configurazione proxy

Personalizza il file `.env`:

```bash
cp .env.example .env
nano .env
```

Crea il file PSK con lo STESSO valore usato nel frontend:

```bash
echo "IL_TUO_PSK_GENERATO_PRIMA" > enc/proxy.psk
chmod 600 enc/proxy.psk
```

**Attenzione**: il file deve contenere solo la stringa esadecimale, senza
newline finale. Se preferisci:

```bash
printf "IL_TUO_PSK" > enc/proxy.psk
```

### 4. Avvia lo stack

```bash
docker compose up -d
```

### 5. Verifica connessione

Sul proxy:

```bash
docker compose logs -f zabbix-proxy
```

Devi vedere messaggi come:
```
proxy #0 started [main process]
```

E NON devi vedere errori tipo `connection refused` o `TLS handshake failed`.

Sul frontend centrale:
- **Administration → Proxies**: deve mostrare il proxy con stato verde e timestamp "Last seen" recente.

## MIB custom

Se ti serve monitorare Ubiquiti o stampanti con MIB non standard, copia i
file `.mib` o `.txt` nella cartella `mibs/` e riavvia il proxy:

```bash
docker compose restart zabbix-proxy
```

I MIB saranno disponibili per tutti gli item SNMP monitorati attraverso
questo proxy.

## Assegnazione host al proxy

Nel frontend centrale, per ogni host che appartiene a questa sede:
**Configuration → Hosts → [host] → Monitored by proxy**: seleziona il proxy.

Oppure usa la Low-Level Discovery per assegnare automaticamente gli host
scoperti su questa rete al proxy corretto.

## Troubleshooting

### Il proxy non si connette
```bash
# Verifica connettività di rete
docker exec zabbix-proxy nc -zv zabbix.msp.example.com 10051

# Verifica log
docker compose logs --tail 100 zabbix-proxy
```

### Errori TLS
Verifica che PSK identity e contenuto PSK coincidano ESATTAMENTE tra
frontend centrale e `.env` + `enc/proxy.psk` lato proxy.

Il PSK deve essere **almeno 32 caratteri esadecimali** (128 bit). Zabbix
consiglia 256 bit = 64 caratteri hex, che è quello che genera
`openssl rand -hex 32`.

### Buffer pieno / dati persi
Se vedi warning "proxy history table is full":
- Aumenta `ZBX_PROXYOFFLINEBUFFER` (ore)
- Aumenta le cache (`ZBX_CACHESIZE`, `ZBX_HISTORYCACHESIZE`)
- Verifica connettività verso il server centrale

## Aggiornamento

```bash
docker compose pull
docker compose up -d
```

Mantieni sempre proxy e server centrale alla stessa versione major/minor.
