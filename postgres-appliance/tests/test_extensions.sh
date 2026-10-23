#!/bin/bash
set -euo pipefail

# Each installed PostgreSQL major gets a fresh, disposable database.
docker run --rm -i --network none --user postgres --entrypoint bash \
    -v "$(cd "$(dirname "$0")" && pwd)/extensions.sql:/tmp/extensions.sql:ro" \
    "${SPILO_TEST_IMAGE:-spilo}" -seu <<'CONTAINER'
tested=0
for pg_release in $POSTGRESQL_VERSIONS; do
    export PATH="/usr/lib/postgresql/${pg_release%%.*}/bin:$PATH"
    [ -x "/usr/lib/postgresql/${pg_release%%.*}/bin/postgres" ] || continue
    postgres --version | grep -F " ${pg_release} "
    PGDATA=$(mktemp -d)
    export PGDATA
    initdb -A trust --encoding=UTF8 --locale=C >/dev/null
    pg_ctl -l "$PGDATA/server.log" -o "-k /tmp -c listen_addresses='' -c wal_level=logical" -w start
    psql -h /tmp -d postgres -v ON_ERROR_STOP=1 -f /tmp/extensions.sql
    pg_ctl -m fast -w stop
    rm -rf "$PGDATA"
    tested=$((tested + 1))
done
[ "$tested" -gt 0 ]
CONTAINER
