#!/bin/sh

set -eu

rpm_dir=${POLARDB_RPM_DIR:-/polardb-rpms}
destination=${POLARDB_ROOTFS:-/polardb-rootfs}

case "${TARGETARCH:-}" in
    arm64)
        rpm_name=PolarDB-2.0.14.41.0-20260421202048.alios7.aarch64.rpm
        expected_sha256=51dee31bd859086c465dec532e616061c83950b3f2626c69a075fbcd85f01622
        ;;
    amd64)
        rpm_name=PolarDB-2.0.14.41.0-20260421202048.alios7.x86_64.rpm
        expected_sha256=c7ba1f7470d5ac946d8a5029081b930c5b379358cd65a2bf843a021e405df553
        ;;
    *)
        echo "unsupported TARGETARCH: ${TARGETARCH:-unset}; expected arm64 or amd64" >&2
        exit 1
        ;;
esac

rpm_path=$rpm_dir/$rpm_name
test -f "$rpm_path" || {
    echo "missing PolarDB RPM: $rpm_path" >&2
    exit 1
}

printf '%s  %s\n' "$expected_sha256" "$rpm_path" | sha256sum -c -

# The vendor RPM is an input archive, not an installation transaction.  Extracting
# its cpio payload with libarchive intentionally does not execute RPM scriptlets
# (%pre/%post/triggers) from this unsigned package.
unexpected_entries=$(bsdtar -tf "$rpm_path" \
    | sed 's#^\./##' \
    | grep -Ev '^u01/polardb_pg(/|$)' || true)
if [ -n "$unexpected_entries" ]; then
    echo "refusing RPM with payload outside /u01/polardb_pg:" >&2
    printf '%s\n' "$unexpected_entries" >&2
    exit 1
fi

mkdir -p "$destination"
bsdtar --no-same-owner -xf "$rpm_path" -C "$destination"

polar_home=$destination/u01/polardb_pg
test -x "$polar_home/bin/postgres"
test -x "$polar_home/bin/initdb"
test -x "$polar_home/bin/polar_basebackup"
test "$(readlink "$polar_home/bin/pg_basebackup")" = polar_basebackup
