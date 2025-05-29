#!/bin/bash

## ----------------
## Locales routines
## ----------------

set -ex

# Configure Aliyun mirrors for better access in China
if [ -f /etc/apt/sources.list ]; then
    cp /etc/apt/sources.list /etc/apt/sources.list.backup
    cat > /etc/apt/sources.list << 'EOF'
# Aliyun Ubuntu mirrors for better access in China
deb http://mirrors.cloud.aliyuncs.com/ubuntu/ bionic main restricted universe multiverse
deb http://mirrors.cloud.aliyuncs.com/ubuntu/ bionic-updates main restricted universe multiverse
deb http://mirrors.cloud.aliyuncs.com/ubuntu/ bionic-security main restricted universe multiverse
deb http://mirrors.cloud.aliyuncs.com/ubuntu/ bionic-backports main restricted universe multiverse

# Fallback to original sources
deb http://archive.ubuntu.com/ubuntu/ bionic main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ bionic-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ bionic-security main restricted universe multiverse
EOF
fi

# Add retry mechanism for apt operations
retry_apt_install() {
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt of $max_attempts..."
        if apt-get install -y --fix-missing "$@"; then
            echo "Installation successful on attempt $attempt"
            return 0
        else
            echo "Installation failed on attempt $attempt"
            if [ $attempt -lt $max_attempts ]; then
                echo "Retrying in 10 seconds..."
                sleep 10
                apt-get update
            fi
            attempt=$((attempt + 1))
        fi
    done

    echo "All attempts failed, trying with --fix-broken"
    apt-get install -y --fix-broken --fix-missing "$@"
}

apt-get update
apt-get -y upgrade
retry_apt_install locales

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
