#!/bin/bash
set -euo pipefail

[[ "${PGVERSION:-}" =~ ^[1-9][0-9]*$ ]] || { echo "PGVERSION must be a PostgreSQL major version" >&2; exit 1; }
supported=${DEB_PG_SUPPORTED_VERSIONS:-${PGOLDVERSIONS:-} $PGVERSION}
if [ "${DEMO:-false}" = true ]; then
    supported=$PGVERSION
fi
seen=" "
for release in ${POSTGRESQL_VERSIONS:-}; do
    [[ "$release" =~ ^[1-9][0-9]*\.(0|[1-9][0-9]*)$ ]] || { echo "Invalid PostgreSQL release: $release (expected major.minor)" >&2; exit 1; }
    major=${release%%.*}
    [[ " $supported " == *" $major "* ]] || { echo "PostgreSQL $release is not selected for installation" >&2; exit 1; }
    [[ "$seen" != *" $major "* ]] || { echo "Multiple release pins for PostgreSQL $major" >&2; exit 1; }
    seen+="$major "
done
