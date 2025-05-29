#!/bin/bash

## ------------------
## Dependencies magic
## ------------------

set -ex

# should exist when $DEMO=TRUE to avoid 'COPY --from=dependencies-builder /builddeps/wal-g ...' failure

if [ "$DEMO" = "true" ]; then
    mkdir /builddeps/wal-g
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive
MAKEFLAGS="-j $(grep -c ^processor /proc/cpuinfo)"
export MAKEFLAGS
ARCH="$(dpkg --print-architecture)"

# We want to remove all libgdal30 debs except one that is for current architecture.
printf "shopt -s extglob\nrm /builddeps/!(*_%s.deb)" "$ARCH" | bash -s

echo -e 'APT::Install-Recommends "0";\nAPT::Install-Suggests "0";' > /etc/apt/apt.conf.d/01norecommend

# Configure Aliyun mirrors for better access in China
if [ -f /etc/apt/sources.list ]; then
    cp /etc/apt/sources.list /etc/apt/sources.list.backup
    cat > /etc/apt/sources.list << 'EOF'
# Aliyun Ubuntu mirrors for better access in China
deb http://mirrors.cloud.aliyuncs.com/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.cloud.aliyuncs.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.cloud.aliyuncs.com/ubuntu/ jammy-security main restricted universe multiverse
deb http://mirrors.cloud.aliyuncs.com/ubuntu/ jammy-backports main restricted universe multiverse

# Fallback to original sources
deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
EOF
fi

apt-get update
apt-get install -y curl ca-certificates

mkdir /builddeps/wal-g

if [ "$ARCH" = "amd64" ]; then
    PKG_NAME='wal-g-pg-ubuntu-20.04-amd64'
else
    PKG_NAME='wal-g-pg-ubuntu20.04-aarch64'
fi

curl -sL "https://github.com/wal-g/wal-g/releases/download/$WALG_VERSION/$PKG_NAME.tar.gz" \
            | tar -C /builddeps/wal-g -xz
mv "/builddeps/wal-g/$PKG_NAME" /builddeps/wal-g/wal-g
