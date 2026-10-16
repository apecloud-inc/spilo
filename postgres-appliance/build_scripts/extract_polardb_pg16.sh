#!/bin/sh

set -eu

rpm_dir=${POLARDB_RPM_DIR:-/polardb-rpms}
destination=${POLARDB_ROOTFS:-/polardb-rootfs}

case "${TARGETARCH:-}" in
    arm64)
        rpm_name=PolarDB16-2.0.16.17.0-20260519173021.al8.aarch64.rpm
        expected_sha256=c05a10970eacb0ffa98c2e09868d2561ac4efd5c5471c362eba36f7a80702b04
        ;;
    amd64)
        rpm_name=PolarDB16-2.0.16.17.0-20260519173021.al8.x86_64.rpm
        expected_sha256=afa962176695179bf20641364c78c2536451d2d4046c7e8bbcb222fb49097a35
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

# Extract the payload without executing vendor RPM scriptlets.
unexpected_entries=$(bsdtar -tf "$rpm_path" \
    | sed 's#^\./##' \
    | grep -Ev '^u01/polardb_pg_16(/|$)' || true)
if [ -n "$unexpected_entries" ]; then
    echo "refusing RPM with payload outside /u01/polardb_pg_16:" >&2
    printf '%s\n' "$unexpected_entries" >&2
    exit 1
fi

mkdir -p "$destination"
bsdtar --no-same-owner -xf "$rpm_path" -C "$destination"

polar_home=$destination/u01/polardb_pg_16
test -x "$polar_home/bin/postgres"
test -x "$polar_home/bin/initdb"
test -x "$polar_home/bin/polar_basebackup"
test "$(readlink "$polar_home/bin/pg_basebackup")" = polar_basebackup
