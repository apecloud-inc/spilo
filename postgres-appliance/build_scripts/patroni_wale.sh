#!/bin/bash

## -------------------------
## Install patroni and wal-e
## -------------------------

export DEBIAN_FRONTEND=noninteractive

set -ex

BUILD_PACKAGES=(python3-pip python3-wheel python3-dev git patchutils binutils gcc)

apt-get update

# Fix any broken dependencies first
apt-get install -y --fix-broken

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

# install most of the patroni dependencies from ubuntu packages
PATRONI_DEPS=$(apt-cache depends patroni \
        | sed -n -e 's/.* Depends: \(python3-.\+\)$/\1/p' \
        | grep -Ev '^python3-(sphinx|etcd|consul|kazoo|kubernetes)' \
        | tr '\n' ' ')

retry_apt_install "${BUILD_PACKAGES[@]}" python3-pystache python3-requests $PATRONI_DEPS

pip3 install setuptools

if [ "$DEMO" != "true" ]; then
    EXTRAS=",etcd,consul,zookeeper,aws"
    retry_apt_install \
        python3-etcd \
        python3-consul \
        python3-kazoo \
        python3-boto \
        python3-boto3 \
        python3-botocore \
        python3-cachetools \
        python3-cffi \
        python3-gevent \
        python3-pyasn1-modules \
        python3-rsa \
        python3-s3transfer \
        python3-swiftclient

    find /usr/share/python-babel-localedata/locale-data -type f ! -name 'en_US*.dat' -delete

    pip3 install filechunkio protobuf \
            'git+https://github.com/zalando-pg/wal-e.git#egg=wal-e[aws,google,swift]' \
            'git+https://github.com/zalando/pg_view.git@master#egg=pg-view'

    # https://github.com/wal-e/wal-e/issues/318
    sed -i 's/^\(    for i in range(0,\) num_retries):.*/\1 100):/g' /usr/lib/python3/dist-packages/boto/utils.py
else
    EXTRAS=""
fi

# NOTE(KubeBlocks): kubeblocks_hack.py requires pyjavaproperties==0.7
pip3 install pyjavaproperties==0.7

pip3 install "patroni[kubernetes$EXTRAS]==$PATRONIVERSION"

for d in /usr/local/lib/python3.10 /usr/lib/python3; do
    cd $d/dist-packages
    find . -type d -name tests -print0 | xargs -0 rm -fr
    find . -type f -name 'test_*.py*' -delete
done
find . -type f -name 'unittest_*.py*' -delete
find . -type f -name '*_test.py' -delete
find . -type f -name '*_test.cpython*.pyc' -delete

# Clean up
apt-get purge -y "${BUILD_PACKAGES[@]}"
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/* \
        /var/cache/debconf/* \
        /root/.cache \
        /usr/share/doc \
        /usr/share/man \
        /usr/share/locale/?? \
        /usr/share/locale/??_?? \
        /usr/share/info
find /var/log -type f -exec truncate --size 0 {} \;
