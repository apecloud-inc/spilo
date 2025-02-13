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

# 等待 dpkg 锁释放
while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
    echo "Waiting for dpkg lock..."
    sleep 2
done

# 修复 dpkg
dpkg --configure -a || true
/sbin/ldconfig || true

# 强制更新 APT 并安装 curl
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates

which curl || { echo "Error: curl not found!"; exit 1; }

mkdir -p /builddeps/wal-g

if [ "$ARCH" = "amd64" ]; then
    PKG_NAME='wal-g-pg-ubuntu-20.04-amd64'
else
    PKG_NAME='wal-g-pg-ubuntu20.04-aarch64'
fi

# 自动重试下载
RETRY=5
until [ "$RETRY" -le 0 ]; do
    curl -sL "https://github.com/wal-g/wal-g/releases/download/$WALG_VERSION/$PKG_NAME.tar.gz" | tar -C /builddeps/wal-g -xz && break
    echo "Download failed, retrying in 5 seconds..."
    sleep 5
    RETRY=$((RETRY - 1))
done

if [ "$RETRY" -le 0 ]; then
    echo "Failed to download WAL-G after multiple attempts."
    exit 1
fi

mv "/builddeps/wal-g/$PKG_NAME" /builddeps/wal-g/wal-g