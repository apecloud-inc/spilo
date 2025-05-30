#!/bin/bash

## ----------------
## Locales routines
## ----------------

set -ex

# Detect actual distribution codename from base image
distro_codename=$(sed -n 's/DISTRIB_CODENAME=//p' /etc/lsb-release)
echo "Detected distribution codename in locales.sh: $distro_codename"

# Configure APT to handle weak security information for arm64
cat > /etc/apt/apt.conf.d/99weak-security << EOF
APT::Get::AllowInsecureRepositories "true";
APT::Get::AllowDowngradeToInsecureRepositories "true";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
EOF

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
apt-get install -y locales

# Cleanup all locales but en_US.UTF-8 and optionally specified in ADDITIONAL_LOCALES arg
find /usr/share/i18n/charmaps/ -type f ! -name UTF-8.gz -delete

# Prepare find expression for locales
LOCALE_FIND_EXPR=(-type f)
for loc in en_US en_GB $ADDITIONAL_LOCALES "i18n*" iso14651_t1 iso14651_t1_common "translit_*"; do
    LOCALE_FIND_EXPR+=(! -name "$loc")
done
find /usr/share/i18n/locales/ "${LOCALE_FIND_EXPR[@]}" -delete

# Make sure we have the en_US.UTF-8 and all additional locales available
truncate --size 0 /usr/share/i18n/SUPPORTED
for loc in en_US $ADDITIONAL_LOCALES; do
    echo "$loc.UTF-8 UTF-8" >> /usr/share/i18n/SUPPORTED
    localedef -i "$loc" -c -f UTF-8 -A /usr/share/locale/locale.alias "$loc.UTF-8"
done
