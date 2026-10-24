#!/bin/bash
set -euo pipefail
validator="$(dirname "$0")/../build_scripts/validate_pg_versions.sh"

accept() {
    env PGOLDVERSIONS= DEB_PG_SUPPORTED_VERSIONS= DEMO=false "$@" bash "$validator"
}
reject() {
    if accept "$@" >/dev/null 2>&1; then
        echo "Unexpectedly accepted: $*" >&2
        exit 1
    fi
}
for release in 12.22 13.23 14.24 15.19 16.15 17.11 18.6 18.7; do
    accept PGVERSION="${release%%.*}" POSTGRESQL_VERSIONS="$release"
done
# Direct, unpinned builds retain their existing package-repository behavior.
accept PGVERSION=18 POSTGRESQL_VERSIONS=
accept PGVERSION=18 PGOLDVERSIONS=17 POSTGRESQL_VERSIONS="17.11 18.6"
accept PGVERSION=18 PGOLDVERSIONS=17 DEMO=true POSTGRESQL_VERSIONS=18.6
reject PGVERSION=18 POSTGRESQL_VERSIONS=17.11
reject PGVERSION=18 POSTGRESQL_VERSIONS="18.6 18.7"
reject PGVERSION=18 POSTGRESQL_VERSIONS="18.6 17.11"
reject PGVERSION=18 PGOLDVERSIONS=17 DEMO=true POSTGRESQL_VERSIONS=17.11
reject PGVERSION=18.6 POSTGRESQL_VERSIONS=18.6
reject PGVERSION= POSTGRESQL_VERSIONS=18.6
for release in 18 18.6.0 18.06 018.6 18.6-1 '18.6*' '18.6;false'; do
    reject PGVERSION=18 POSTGRESQL_VERSIONS="$release"
done
printf '%s\n' 'PostgreSQL build version argument tests passed'
