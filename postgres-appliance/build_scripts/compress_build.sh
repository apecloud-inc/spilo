#!/bin/bash

set -ex

# Detect actual distribution codename from base image
distro_codename=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2 | tr -d '"' || lsb_release -cs 2>/dev/null || echo "jammy")
echo "Detected distribution codename in compress_build.sh: $distro_codename"

# Configure mirrors based on architecture
ARCH=$(dpkg --print-architecture)
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
apt-get install -y busybox xz-utils
apt-get clean

rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /usr/share/doc /usr/share/man /etc/rc?.d /etc/systemd
ln -snf busybox /bin/sh

files="/bin/sh"
arch=$(uname -m)
darch=$(uname -m | sed 's/_/-/')

IFS=" " read -r -a libs <<< "$(ldd $files | awk '{print $3;}' | grep '^/' | sort -u)"
libs+=(/lib/ld-linux-"$darch".so.* \
    /lib/"$arch"-linux-gnu/ld-linux-"$darch".so.* \
    /lib/"$arch"-linux-gnu/libnsl.so.* \
    /lib/"$arch"-linux-gnu/libnss_compat.so.*)

(echo /var/run /var/spool "$files" "${libs[@]}" | tr ' ' '\n' && realpath "$files" "${libs[@]}") | sort -u | sed 's/^\///' > /exclude

find /etc/alternatives -xtype l -delete
save_dirs=(usr lib var bin sbin etc/ssl etc/init.d etc/alternatives etc/apt)
XZ_OPT=-e9v tar -X /exclude -cpJf a.tar.xz "${save_dirs[@]}"

rm -fr /usr/local/lib/python*

/bin/busybox sh -c "(find ${save_dirs[*]} -not -type d && cat /exclude /exclude && echo exclude) | sort | uniq -u | xargs /bin/busybox rm"
/bin/busybox --install -s
/bin/busybox sh -c "find ${save_dirs[*]} -type d -depth -exec rmdir -p {}; 2> /dev/null"
