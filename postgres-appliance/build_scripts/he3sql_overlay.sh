#!/bin/bash
# Overlay he3sql PostgreSQL binaries over the apt-installed version.

set -ex

if [ "$HE3SQL" != "true" ] || [ ! -d /he3sql/bin ]; then
    exit 0
fi

# Detect he3sql PG version from its pg_config
HE3SQL_VERSION=$(/he3sql/bin/pg_config --version | sed 's/.* \([0-9]\+\).*/\1/')
[ -n "$HE3SQL_VERSION" ] || exit 1

echo "Overlaying he3sql PostgreSQL $HE3SQL_VERSION ..."

# he3sql was compiled against OpenSSL 1.1; libssl.so.1.1/libcrypto.so.1.1
# are pre-installed via the focal-libssl multi-stage COPY in the Dockerfile.

# he3sql binaries have hardcoded RPATH /he3data/ptw/he3sql/lib from build time.
# Create a symlink so the dynamic linker finds libraries at runtime.
mkdir -p /he3data/ptw/he3sql
ln -sfn "/usr/lib/postgresql/$HE3SQL_VERSION/lib" /he3data/ptw/he3sql/lib

# initdb/postgres derive SHAREDIR from the binary's own location:
#   /usr/lib/postgresql/<ver>/bin/initdb → ../share/postgresql/
# Link it to where the he3sql share files actually live.
ln -sfn "/usr/share/postgresql/$HE3SQL_VERSION" \
    "/usr/lib/postgresql/$HE3SQL_VERSION/share"

# Ensure target directories exist
mkdir -p "/usr/lib/postgresql/$HE3SQL_VERSION/bin"
mkdir -p "/usr/lib/postgresql/$HE3SQL_VERSION/lib"
mkdir -p "/usr/lib/postgresql/$HE3SQL_VERSION/share"
mkdir -p /usr/include/postgresql

# Remove existing bin files — some may be symlinks to the highest PG version
rm -f "/usr/lib/postgresql/$HE3SQL_VERSION/bin/"*

# Copy he3sql files over the top
cp -r /he3sql/bin/*    "/usr/lib/postgresql/$HE3SQL_VERSION/bin/"
cp -r /he3sql/lib/*    "/usr/lib/postgresql/$HE3SQL_VERSION/lib/"
cp -r /he3sql/share/postgresql/* "/usr/share/postgresql/$HE3SQL_VERSION/"
cp -r /he3sql/include/* "/usr/include/postgresql/"

echo "he3sql PostgreSQL $HE3SQL_VERSION overlay complete"
