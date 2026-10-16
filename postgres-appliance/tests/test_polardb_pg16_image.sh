#!/usr/bin/env bash

set -euo pipefail

image=${1:-apecloud/polardb-pg:2.0.16.17.0-local-arm64}
docker image inspect "$image" >/dev/null

docker run --rm --entrypoint /bin/bash "$image" -ceu '
    postgres --version | grep -Fx "postgres (PostgreSQL) 16.13"
    test "$(readlink -f /usr/lib/postgresql/16/bin/postgres)" = /u01/polardb_pg_16/bin/postgres
    test "$(readlink -f /usr/lib/postgresql/16/bin/pg_basebackup)" = /u01/polardb_pg_16/bin/polar_basebackup
    test "$(pg_config --bindir)" = /u01/polardb_pg_16/bin
    test ! -e /polardb-rpms
    ! ldd /u01/polardb_pg_16/bin/postgres | grep -q "not found"
    patronictl version | grep -E "patronictl version 4\.1\.0"
'

docker run --rm --user postgres --entrypoint /bin/bash "$image" -ceu '
    data_dir=$(mktemp -d /tmp/polardb-initdb.XXXXXX)
    initdb --no-locale -D "$data_dir" >/tmp/initdb.log 2>&1 || {
        cat /tmp/initdb.log >&2
        exit 1
    }
    test "$(cat "$data_dir/PG_VERSION")" = 16
    test ! -e "$data_dir/global/POLARDB_CATALOG_INFO"
    pg_ctl -D "$data_dir" -o "-c listen_addresses= -c unix_socket_directories=/tmp" -w start >/tmp/start.log 2>&1 || {
        cat /tmp/start.log >&2
        exit 1
    }
    psql -h /tmp -d postgres -Atc "create table smoke (id int); insert into smoke values (16); select id from smoke" | grep -Fx 16
    pg_basebackup -h /tmp -U postgres -D "$data_dir.backup" -Ft -Xs >/tmp/basebackup.log 2>&1 || {
        cat /tmp/basebackup.log >&2
        exit 1
    }
    tar tf "$data_dir.backup/base.tar" | grep -Fx PG_VERSION
    pg_ctl -D "$data_dir" -m immediate -w stop >/dev/null
    mkdir -m 0700 "$data_dir.restored"
    tar xf "$data_dir.backup/base.tar" -C "$data_dir.restored"
    test ! -e "$data_dir.backup/pg_wal.tar" || tar xf "$data_dir.backup/pg_wal.tar" -C "$data_dir.restored/pg_wal"
    pg_ctl -D "$data_dir.restored" -o "-c listen_addresses= -c unix_socket_directories=/tmp" -w start >/tmp/restore.log 2>&1 || {
        cat /tmp/restore.log >&2
        exit 1
    }
    psql -h /tmp -d postgres -Atc "select id from smoke" | grep -Fx 16
    pg_ctl -D "$data_dir.restored" -m immediate -w stop >/dev/null
'

docker run --rm --entrypoint /bin/bash \
    --env PGROOT=/tmp/pgroot \
    --env PGDATA=/tmp/pgroot/data \
    --env RW_DIR=/tmp/run \
    --env SCOPE=polardb-smoke \
    --env PGUSER_SUPERUSER=postgres \
    --env PGPASSWORD_SUPERUSER=postgres \
    --env PGUSER_STANDBY=standby \
    --env PGPASSWORD_STANDBY=standby \
    --env POLARDB_COMPATIBILITY_MODE=pg \
    --env SPILO_CONFIGURATION=$'bootstrap:\n  initdb:\n    - compatibility_mode: pg' \
    "$image" -ceu '
        mkdir -p "$PGROOT" "$PGDATA" "$PGLOG" \
            "$RW_DIR/postgresql" "$RW_DIR/tmp" "$RW_DIR/certs"
        configure_rc=0
        python3 /scripts/configure_spilo.py all || configure_rc=$?
        test "$configure_rc" -eq 0 || test "$configure_rc" -eq 1
        python3 - <<"PY"
import os
import yaml

with open(os.path.join(os.environ["RW_DIR"], "postgres.yml"), encoding="utf-8") as stream:
    config = yaml.safe_load(stream)
assert config["postgresql"]["bin_dir"] == "/usr/lib/postgresql/16/bin"
assert not any(
    isinstance(option, dict) and "compatibility_mode" in option
    for option in config["bootstrap"]["initdb"]
)
assert config["bootstrap"]["dcs"]["postgresql"]["parameters"][
    "polar_resource_manager.enable_resource_manager"
] == "off"
PY
    '

if docker run --rm --entrypoint python3 \
    --env POLARDB_COMPATIBILITY_MODE=ora \
    --env PYTHONPATH=/scripts \
    "$image" -c 'import configure_polardb_spilo; configure_polardb_spilo.apply_polardb_defaults()' \
    >/dev/null 2>&1; then
    echo 'PolarDB-PG 16 unexpectedly accepted ora mode' >&2
    exit 1
fi

echo "PolarDB-PG 16 image smoke passed: $image"
