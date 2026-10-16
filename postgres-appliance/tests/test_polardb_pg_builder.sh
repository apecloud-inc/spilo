#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
build_script="${repo_root}/hack/build-polardb-pg.sh"
fixture_bin="${repo_root}/postgres-appliance/tests/fixtures/polardb_builder"
tmp_dir=$(mktemp -d)
trap 'rm -rf "${tmp_dir}"' EXIT

rpm_dir="${tmp_dir}/rpms"
calls_file="${tmp_dir}/docker.calls"
build_args_file="${tmp_dir}/build.args"
mkdir -p "${rpm_dir}"
touch \
    "${rpm_dir}/PolarDB-2.0.14.41.0-20260421202048.alios7.x86_64.rpm" \
    "${rpm_dir}/PolarDB-2.0.14.41.0-20260421202048.alios7.aarch64.rpm"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

run_build() {
    local output=$1 image=$2
    shift 2
    : >"${calls_file}"
    rm -f "${build_args_file}"
    env \
        PATH="${fixture_bin}:${PATH}" \
        POLARDB_MOCK_DOCKER_CALLS="${calls_file}" \
        POLARDB_MOCK_BUILD_ARGS="${build_args_file}" \
        "$@" \
        bash "${build_script}" "${rpm_dir}" "${image}" >"${output}" 2>&1
}

expect_failure() {
    local name=$1 expected=$2 image=$3 output
    output="${tmp_dir}/${name}.log"
    shift 3
    if run_build "${output}" "${image}" "$@"; then
        fail "${name} unexpectedly succeeded"
    fi
    grep -Fq "${expected}" "${output}" || {
        sed -n '1,120p' "${output}" >&2
        fail "${name} did not report the expected rejection: ${expected}"
    }
}

local_image=apecloud/polardb-pg:2.0.14.41.0-local
public_acr=apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/polardb-pg:2.0.14.41.0

expect_failure missing-builder 'every build requires an explicit POLARDB_BUILDER' "${local_image}" \
    PLATFORM=linux/arm64 POLARDB_BUILD_PREFLIGHT_ONLY=true
[[ ! -s "${calls_file}" ]] || fail 'missing-builder rejection invoked Docker'

expect_failure unsupported-platform 'unsupported PLATFORM: linux/s390x' "${local_image}" \
    PLATFORM=linux/s390x POLARDB_BUILDER=polardb-local POLARDB_BUILD_PREFLIGHT_ONLY=true
[[ ! -s "${calls_file}" ]] || fail 'unsupported-platform rejection invoked Docker'

expect_failure remote-endpoint 'builder node is not bound to a local Unix Docker endpoint' "${local_image}" \
    PLATFORM=linux/arm64 POLARDB_BUILDER=polardb-remote POLARDB_MOCK_BUILDER_SCENARIO=remote \
    POLARDB_BUILD_PREFLIGHT_ONLY=true

expect_failure mixed-endpoints 'builder node is not bound to a local Unix Docker endpoint' "${local_image}" \
    PLATFORM=linux/arm64 POLARDB_BUILDER=polardb-mixed POLARDB_MOCK_BUILDER_SCENARIO=mixed \
    POLARDB_BUILD_PREFLIGHT_ONLY=true

expect_failure missing-platform 'builder does not advertise linux/arm64' "${local_image}" \
    PLATFORM=linux/arm64 POLARDB_BUILDER=polardb-amd64 POLARDB_MOCK_BUILDER_SCENARIO=amd64-only \
    POLARDB_BUILD_PREFLIGHT_ONLY=true

expect_failure shared-docker-driver 'proprietary RPM builds require a dedicated docker-container buildx driver' "${local_image}" \
    PLATFORM=linux/arm64 POLARDB_BUILDER=shared-engine POLARDB_MOCK_BUILDER_SCENARIO=docker-driver \
    POLARDB_BUILD_PREFLIGHT_ONLY=true

expect_failure remote-docker-host 'refusing a non-local DOCKER_HOST' "${local_image}" \
    PLATFORM=linux/arm64 POLARDB_BUILDER=polardb-local DOCKER_HOST=tcp://builder.example.invalid:2376 \
    POLARDB_BUILD_PREFLIGHT_ONLY=true

expect_failure base-override 'SPILO_BASE_IMAGE overrides are forbidden' "${local_image}" \
    PLATFORM=linux/arm64 POLARDB_BUILDER=polardb-local SPILO_BASE_IMAGE=example.invalid/spilo:override \
    POLARDB_BUILD_PREFLIGHT_ONLY=true
[[ ! -s "${calls_file}" ]] || fail 'base-image override rejection invoked Docker'

expect_failure extractor-override 'POLARDB_EXTRACTOR_IMAGE overrides are forbidden' "${local_image}" \
    PLATFORM=linux/arm64 POLARDB_BUILDER=polardb-local POLARDB_EXTRACTOR_IMAGE=example.invalid/extractor:override \
    POLARDB_BUILD_PREFLIGHT_ONLY=true
[[ ! -s "${calls_file}" ]] || fail 'extractor-image override rejection invoked Docker'

expect_failure unapproved-publish-target 'refusing publish target outside the approved private ACR repository' \
    docker.io/apecloud/polardb-pg:2.0.14.41.0 \
    PLATFORM=linux/amd64,linux/arm64 POLARDB_BUILDER=polardb-local POLARDB_PUSH=true \
    POLARDB_PUBLISH_PREFLIGHT_ONLY=true POLARDB_PRIVATE_REPOSITORY_CONFIRMED=true \
    POLARDB_TRUSTED_BUILDER_CONFIRMED=true

expect_failure non-dedicated-builder 'building requires POLARDB_DEDICATED_BUILDER_CONFIRMED=true' "${local_image}" \
    PLATFORM=linux/arm64 POLARDB_BUILDER=polardb-local POLARDB_BUILD_PREFLIGHT_ONLY=true
if grep -Fq 'buildx build' "${calls_file}" || grep -Fq 'buildx prune' "${calls_file}"; then
    fail 'non-dedicated-builder rejection built or pruned'
fi

preflight_output="${tmp_dir}/preflight.log"
run_build "${preflight_output}" "${public_acr}" \
    PLATFORM=linux/amd64,linux/arm64 POLARDB_BUILDER=polardb-local POLARDB_PUSH=true \
    POLARDB_PUBLISH_PREFLIGHT_ONLY=true POLARDB_PRIVATE_REPOSITORY_CONFIRMED=true \
    POLARDB_TRUSTED_BUILDER_CONFIRMED=true POLARDB_DEDICATED_BUILDER_CONFIRMED=true
grep -Fq 'PolarDB-PG build preflight passed' "${preflight_output}" \
    || fail 'trusted publish preflight did not pass'
if grep -Fq 'buildx build' "${calls_file}"; then
    fail 'publish preflight entered buildx build'
fi
[[ ! -e "${build_args_file}" ]] || fail 'publish preflight produced build arguments'

mock_build_output="${tmp_dir}/mock-build.log"
run_build "${mock_build_output}" "${local_image}" \
    PLATFORM=linux/arm64 POLARDB_BUILDER=polardb-local POLARDB_DEDICATED_BUILDER_CONFIRMED=true
grep -Fq 'built apecloud/polardb-pg:2.0.14.41.0-local for linux/arm64 (push=false)' "${mock_build_output}" \
    || fail 'trusted mock local build did not complete'
grep -Fqx -- '--builder' "${build_args_file}" || fail 'mock build omitted explicit builder flag'
grep -Fqx 'polardb-local' "${build_args_file}" || fail 'mock build omitted explicit builder name'
grep -Fqx -- '--load' "${build_args_file}" || fail 'mock local build omitted --load'
awk -v expected="polardb_rpms=${rpm_dir}" '
    $0 == "--build-context" {getline; found=($0 == expected)}
    END {exit !found}
' "${build_args_file}" || fail 'mock build omitted the exact adjacent local RPM named-context arguments'
if grep -Fq -- '--secret' "${build_args_file}"; then
    fail 'mock build retained the unusable BuildKit secret transport for large RPMs'
fi
grep -Fqx 'SPILO_BASE_IMAGE=apecloud/spilo:14.23@sha256:e6b514f0b79f8beba3183fd1e1e1070d27d8948032c89944738c8a0f0407dafe' \
    "${build_args_file}" || fail 'mock build did not retain the pinned Spilo base image'
grep -Fqx 'POLARDB_EXTRACTOR_IMAGE=ubuntu:22.04@sha256:2edbbc5dc405e9612ba3584ce95480277e3eb374407b5505fe26f17df77c7dbc' \
    "${build_args_file}" || fail 'mock build did not retain the pinned extractor image'
grep -Fq 'buildx prune --builder polardb-local --all --force' "${calls_file}" \
    || fail 'mock build did not prune the dedicated local builder cache'
awk '
    /^RUN / {block=$0; collecting=($0 ~ /\\$/); if (!collecting) block=""; next}
    collecting {
        block=block "\n" $0
        if ($0 !~ /\\$/) {
            if (block ~ /^RUN --network=none/ && block ~ /--mount=type=bind,from=polardb_rpms,target=\/polardb-rpms/) found=1
            collecting=0
            block=""
        }
    }
    END {exit !found}
' "${repo_root}/postgres-appliance/Dockerfile.polardb-pg" \
    || fail 'Dockerfile RPM bind mount is not part of one RUN --network=none instruction'
if grep -Fq -- '--mount=type=secret' "${repo_root}/postgres-appliance/Dockerfile.polardb-pg"; then
    fail 'Dockerfile retained the unusable BuildKit secret transport for large RPMs'
fi

failed_build_output="${tmp_dir}/failed-build.log"
if run_build "${failed_build_output}" "${local_image}" \
    PLATFORM=linux/arm64 POLARDB_BUILDER=polardb-local POLARDB_DEDICATED_BUILDER_CONFIRMED=true \
    POLARDB_MOCK_BUILD_MODE=fail; then
    fail 'mock build failure was reported successful'
fi
build_line=$(grep -n -m1 '^buildx build ' "${calls_file}" | cut -d: -f1)
prune_line=$(grep -n -m1 '^buildx prune ' "${calls_file}" | cut -d: -f1)
[[ -n "${build_line}" && -n "${prune_line}" && "${prune_line}" -gt "${build_line}" ]] \
    || fail 'failed build did not prune the dedicated builder afterward'

failed_prune_output="${tmp_dir}/failed-prune.log"
if run_build "${failed_prune_output}" "${local_image}" \
    PLATFORM=linux/arm64 POLARDB_BUILDER=polardb-local POLARDB_DEDICATED_BUILDER_CONFIRMED=true \
    POLARDB_MOCK_PRUNE_MODE=fail; then
    fail 'mock prune failure was reported successful'
fi
grep -Fq 'failed to prune dedicated builder cache for polardb-local' "${failed_prune_output}" \
    || fail 'mock prune failure lacks a fail-closed diagnostic'
build_line=$(grep -n -m1 '^buildx build ' "${calls_file}" | cut -d: -f1)
prune_line=$(grep -n -m1 '^buildx prune ' "${calls_file}" | cut -d: -f1)
[[ -n "${build_line}" && -n "${prune_line}" && "${prune_line}" -gt "${build_line}" ]] \
    || fail 'failed prune was not attempted after the build'

rpm_dir="${tmp_dir}/rpms-16"
mkdir -p "${rpm_dir}"
touch \
    "${rpm_dir}/PolarDB16-2.0.16.17.0-20260519173021.al8.x86_64.rpm" \
    "${rpm_dir}/PolarDB16-2.0.16.17.0-20260519173021.al8.aarch64.rpm"
run_build "${tmp_dir}/pg16-build.log" apecloud/polardb-pg:2.0.16.17.0-local \
    POLARDB_RELEASE=2.0.16 PLATFORM=linux/arm64 POLARDB_BUILDER=polardb-local \
    POLARDB_DEDICATED_BUILDER_CONFIRMED=true
grep -Fqx 'postgres-appliance/Dockerfile.polardb-pg16' "${build_args_file}" \
    || fail 'PG16 build did not select the PG16 Dockerfile'
grep -Fqx 'SPILO_BASE_IMAGE=apecloud/spilo:16.14@sha256:b8522b0bbbfd6d08a1aee3c03f61ff427c7ce6938e15f03d78b2955fd7a981e9' \
    "${build_args_file}" || fail 'PG16 build did not select the pinned Spilo 16 base'
run_build "${tmp_dir}/pg16-publish-preflight.log" \
    apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/polardb-pg:2.0.16.17.0 \
    POLARDB_RELEASE=2.0.16 PLATFORM=linux/amd64,linux/arm64 POLARDB_BUILDER=polardb-local \
    POLARDB_PUSH=true POLARDB_PUBLISH_PREFLIGHT_ONLY=true \
    POLARDB_PRIVATE_REPOSITORY_CONFIRMED=true POLARDB_TRUSTED_BUILDER_CONFIRMED=true \
    POLARDB_DEDICATED_BUILDER_CONFIRMED=true
grep -Fq 'PolarDB-PG build preflight passed' "${tmp_dir}/pg16-publish-preflight.log" \
    || fail 'PG16 publish preflight did not accept the pinned private image tag'
[[ ! -e "${build_args_file}" ]] || fail 'PG16 publish preflight invoked BuildKit'

echo 'PASS: PolarDB-PG proprietary builder safety contracts'
