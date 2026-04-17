#!/bin/bash
# ==============================================================================
# Abilita l'estensione TimescaleDB nel database Zabbix
# Viene eseguito automaticamente alla prima inizializzazione del container
# postgres grazie al mount /docker-entrypoint-initdb.d
# ==============================================================================

set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
EOSQL

echo "TimescaleDB extension enabled on database $POSTGRES_DB"
echo ""
echo "==================================================================="
echo "IMPORTANTE: dopo il primo avvio del server Zabbix (che crea lo"
echo "schema), esegui manualmente lo script di conversione hypertables:"
echo ""
echo "  docker exec -it zabbix-postgres psql -U zabbix -d zabbix \\"
echo "    -f /usr/share/doc/zabbix-sql-scripts/postgresql/timescaledb.sql"
echo ""
echo "Se il file non è presente nel container postgres, prendilo dal"
echo "container zabbix-server:"
echo ""
echo "  docker cp zabbix-server:/usr/share/doc/zabbix-server-postgresql/timescaledb.sql.gz ."
echo "  gunzip timescaledb.sql.gz"
echo "  docker cp timescaledb.sql zabbix-postgres:/tmp/"
echo "  docker exec -it zabbix-postgres psql -U zabbix -d zabbix -f /tmp/timescaledb.sql"
echo ""
echo "Poi abilita compressione dal frontend:"
echo "Administration -> General -> Housekeeping -> Enable compression"
echo "==================================================================="
