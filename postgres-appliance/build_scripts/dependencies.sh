#!/bin/bash

set -ex

if [ "$DEMO" = "true" ]; then
    mkdir -p /builddeps/wal-g
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive
export MAKEFLAGS="-j$(nproc)"
ARCH="$(dpkg --print-architecture)"

find /builddeps -type f ! -name "*_${ARCH}.deb" -delete

echo -e 'APT::Install-Recommends "0";\nAPT::Install-Suggests "0";' | tee /etc/apt/apt.conf.d/01norecommend

while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
    echo "Waiting for dpkg lock..."
    sleep 2
done

dpkg --configure -a || true
/sbin/ldconfig || true

for i in {1..3}; do
    apt-get update && break || sleep 5
done

apt-get install -y --no-install-recommends curl ca-certificates libc-bin || true
dpkg --force-all --configure -a || true
/sbin/ldconfig || true

mkdir -p /builddeps/wal-g

if [ "$ARCH" = "amd64" ]; then
    PKG_NAME='wal-g-pg-ubuntu-20.04-amd64'
else
    PKG_NAME='wal-g-pg-ubuntu20.04-aarch64'
fi

curl -sL "https://github.com/wal-g/wal-g/releases/download/$WALG_VERSION/$PKG_NAME.tar.gz" \
    | tar -C /builddeps/wal-g -xz
mv "/builddeps/wal-g/$PKG_NAME" /builddeps/wal-g/wal-g