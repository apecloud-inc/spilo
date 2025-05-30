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

# Detect actual distribution codename from base image
distro_codename=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2 | tr -d '"' || lsb_release -cs 2>/dev/null || echo "jammy")
echo "Detected distribution codename in dependencies.sh: $distro_codename"

# Configure mirrors based on architecture
if [ -f /etc/apt/sources.list ]; then
    cp /etc/apt/sources.list /etc/apt/sources.list.backup
    if [ "$ARCH" = "arm64" ]; then
        # Use official Ubuntu ports mirror for arm64
        cat > /etc/apt/sources.list << EOF
# Official Ubuntu ports mirror for arm64
deb http://ports.ubuntu.com/ubuntu-ports/ ${distro_codename} main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ ${distro_codename}-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ ${distro_codename}-security main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ ${distro_codename}-backports main restricted universe multiverse
EOF
    else
        # Use Aliyun Ubuntu mirrors for better access in China (for amd64 and others)
        cat > /etc/apt/sources.list << EOF
# Aliyun Ubuntu mirrors for better access in China
deb http://mirrors.cloud.aliyuncs.com/ubuntu/ ${distro_codename} main restricted universe multiverse
deb http://mirrors.cloud.aliyuncs.com/ubuntu/ ${distro_codename}-updates main restricted universe multiverse
deb http://mirrors.cloud.aliyuncs.com/ubuntu/ ${distro_codename}-security main restricted universe multiverse
deb http://mirrors.cloud.aliyuncs.com/ubuntu/ ${distro_codename}-backports main restricted universe multiverse

# Fallback to original sources
deb http://archive.ubuntu.com/ubuntu/ ${distro_codename} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ ${distro_codename}-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ ${distro_codename}-security main restricted universe multiverse
EOF
    fi
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
