#!/usr/bin/env bash

set -euo pipefail

image=${1:-${POLARDB_PG_TEST_IMAGE:-apecloud/polardb-pg:2.0.14.41.0-local}}

docker image inspect "$image" >/dev/null

docker run --rm --entrypoint /bin/bash "$image" -ceu '
    postgres --version | grep -E "postgres \(PostgreSQL\) 14\.20"
    test "$(readlink -f /usr/lib/postgresql/14/bin/postgres)" = /u01/polardb_pg/bin/postgres
    test "$(readlink -f /usr/lib/postgresql/14/bin/pg_basebackup)" = /u01/polardb_pg/bin/polar_basebackup
    test "$(pg_config --bindir)" = /u01/polardb_pg/bin
    test ! -e /polardb-rpms
    test -z "$(find / -xdev -type f \( \
        -name "PolarDB-2.0.14.41.0-20260421202048.alios7.x86_64.rpm" -o \
        -name "PolarDB-2.0.14.41.0-20260421202048.alios7.aarch64.rpm" \
      \) -print -quit 2>/dev/null)"
    ! ldd /u01/polardb_pg/bin/postgres | grep -q "not found"
    patronictl version | grep -E "patronictl version 4\.1\.0"
'

for mode in pg ora; do
    docker run --rm --user postgres --entrypoint /bin/bash \
        --env POLARDB_TEST_MODE="$mode" \
        "$image" -ceu '
        data_dir=$(mktemp -d /tmp/polardb-initdb.XXXXXX)
        initdb -m "$POLARDB_TEST_MODE" --no-locale -D "$data_dir"
        test "$(cat "$data_dir/PG_VERSION")" = 14
    '
done

docker run --rm --entrypoint /bin/bash \
    --env PGROOT=/tmp/pgroot \
    --env PGDATA=/tmp/pgroot/data \
    --env RW_DIR=/tmp/run \
    --env SCOPE=polardb-smoke \
    --env PGUSER_SUPERUSER=postgres \
    --env PGPASSWORD_SUPERUSER=postgres \
    --env PGUSER_STANDBY=standby \
    --env PGPASSWORD_STANDBY=standby \
    --env POLARDB_COMPATIBILITY_MODE=ora \
    "$image" -ceu '
        # Mirror the directories launch.sh creates before invoking the normal
        # DEMO=false configurator path.
        mkdir -p "$PGROOT" "$PGDATA" "$PGLOG" \
            "$RW_DIR/postgresql" "$RW_DIR/tmp" "$RW_DIR/certs"
        configure_rc=0
        # /launch.sh uses the "all" path when DEMO=false, which is the production
        # default. Testing only "patroni" would miss the normal startup branch.
        python3 /scripts/configure_spilo.py all || configure_rc=$?
        test "$configure_rc" -eq 0 || test "$configure_rc" -eq 1
        python3 - <<"PY"
import os
import yaml

with open(os.path.join(os.environ["RW_DIR"], "postgres.yml"), encoding="utf-8") as stream:
    config = yaml.safe_load(stream)

local = config["postgresql"]
assert local["bin_dir"] == "/usr/lib/postgresql/14/bin"
assert local["parameters"]["shared_preload_libraries"] == ""
assert "polar_worker.enable_standby_wal_prealloc" not in local["parameters"]
assert "polar_resource_manager.enable_resource_manager" not in local["parameters"]
dcs_parameters = config["bootstrap"]["dcs"]["postgresql"]["parameters"]
assert dcs_parameters["polar_worker.enable_standby_wal_prealloc"] == "off"
assert dcs_parameters["polar_resource_manager.enable_resource_manager"] == "off"
assert {"compatibility_mode": "ora"} in config["bootstrap"]["initdb"]
PY
    '

echo "PolarDB-PG image smoke passed: $image"
