#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

echo -e 'APT::Install-Recommends "0";\nAPT::Install-Suggests "0";' > /etc/apt/apt.conf.d/01norecommend

# Configure APT to handle weak security information for arm64
cat > /etc/apt/apt.conf.d/99weak-security << EOF
APT::Get::AllowInsecureRepositories "true";
APT::Get::AllowDowngradeToInsecureRepositories "true";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
EOF

# Detect actual distribution codename from base image
distro_codename=$(sed -n 's/DISTRIB_CODENAME=//p' /etc/lsb-release)
echo "Detected actual distribution codename: $distro_codename"

# Configure mirrors based on architecture
ARCH=$(dpkg --print-architecture)
if [ -f /etc/apt/sources.list ]; then
    cp /etc/apt/sources.list /etc/apt/sources.list.backup
    if [ "$ARCH" = "arm64" ]; then
        # Use official Ubuntu ports mirror for arm64
        cat > /etc/apt/sources.list << EOF
# Official Ubuntu ports mirror for arm64
deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports/ ${distro_codename} main restricted universe multiverse
deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports/ ${distro_codename}-updates main restricted universe multiverse
deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports/ ${distro_codename}-security main restricted universe multiverse
deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports/ ${distro_codename}-backports main restricted universe multiverse
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
apt-get -y upgrade
apt-get install -y curl ca-certificates less locales jq vim-tiny gnupg1 cron runit dumb-init libcap2-bin rsync sysstat gpg

ln -s chpst /usr/bin/envdir

# Make it possible to use the following utilities without root (if container runs without "no-new-privileges:true")
setcap 'cap_sys_nice+ep' /usr/bin/chrt
setcap 'cap_sys_nice+ep' /usr/bin/renice

# Disable unwanted cron jobs
rm -fr /etc/cron.??*
truncate --size 0 /etc/crontab

if [ "$DEMO" != "true" ]; then
    # Required for wal-e
    apt-get install -y pv lzop
    # install etcdctl
    ETCDVERSION=3.3.27
    curl -L https://github.com/coreos/etcd/releases/download/v${ETCDVERSION}/etcd-v${ETCDVERSION}-linux-"$(dpkg --print-architecture)".tar.gz \
                | tar xz -C /bin --strip=1 --wildcards --no-anchored --no-same-owner etcdctl etcd
fi

# Dirty hack for smooth migration of existing dbs
bash /builddeps/locales.sh
mv /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.22
ln -s /run/locale-archive /usr/lib/locale/locale-archive
ln -s /usr/lib/locale/locale-archive.22 /run/locale-archive

# Add PGDG repositories
DISTRIB_CODENAME=$(sed -n 's/DISTRIB_CODENAME=//p' /etc/lsb-release)
for t in deb deb-src; do
    echo "$t http://apt.postgresql.org/pub/repos/apt/ ${DISTRIB_CODENAME}-pgdg main" >> /etc/apt/sources.list.d/pgdg.list
done
curl -s -o - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg

# add TimescaleDB repository
echo "deb [signed-by=/etc/apt/keyrings/timescale_timescaledb-archive-keyring.gpg] https://packagecloud.io/timescale/timescaledb/ubuntu/ ${DISTRIB_CODENAME} main" | tee /etc/apt/sources.list.d/timescaledb.list
curl -fsSL https://packagecloud.io/timescale/timescaledb/gpgkey | gpg --dearmor | tee /etc/apt/keyrings/timescale_timescaledb-archive-keyring.gpg > /dev/null

# NOTE(KubeBlocks): Add Pigsty's GPG public key to your system keychain to verify package signatures
# https://pigsty.io/ext/repo/apt/
curl -fsSL https://repo.pigsty.cc/key | gpg --dearmor -o /etc/apt/keyrings/pigsty.gpg
# Get Debian distribution codename - try multiple methods
echo "Using distribution codename for Pigsty: $DISTRIB_CODENAME"
tee /etc/apt/sources.list.d/pigsty-io.list > /dev/null <<EOF
deb [signed-by=/etc/apt/keyrings/pigsty.gpg] https://repo.pigsty.cc/apt/infra generic main
deb [signed-by=/etc/apt/keyrings/pigsty.gpg] https://repo.pigsty.cc/apt/pgsql/${DISTRIB_CODENAME} ${DISTRIB_CODENAME} main
EOF

# Clean up
apt-get purge -y libcap2-bin
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/* \
            /var/cache/debconf/* \
            /usr/share/doc \
            /usr/share/man \
            /usr/share/locale/?? \
            /usr/share/locale/??_??
find /var/log -type f -exec truncate --size 0 {} \;
