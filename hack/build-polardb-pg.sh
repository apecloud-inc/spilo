#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: build-polardb-pg.sh RPM_DIRECTORY [IMAGE]

Build the PolarDB-PG Spilo image for the local architecture. RPM_DIRECTORY is
allowed to contain only the two pinned vendor RPMs. That exact directory is
passed as a read-only named context to an explicit local BuildKit builder; no
RPM is copied into this Git repository or a retained image layer. The selected
builder must be dedicated because its cache is pruned after every real build.

Environment:
  PLATFORM          Build platform(s); defaults to the native linux/amd64 or
                    linux/arm64 platform. Publishing requires the exact
                    linux/amd64,linux/arm64 pair.
  POLARDB_PUSH      Set to true to push a multi-architecture manifest. The
                    target repository must already be verified private.
  POLARDB_PRIVATE_REPOSITORY_CONFIRMED
                    Set to true only after independently confirming that the
                    target Alibaba Cloud ACR repository is private.
  POLARDB_TRUSTED_BUILDER_CONFIRMED
                    Set to true only for publishing, after confirming the
                    selected buildx builder is the local authorized engine.
  POLARDB_DEDICATED_BUILDER_CONFIRMED
                    Set to true after confirming the selected builder is
                    dedicated to this proprietary build and may be pruned.
  POLARDB_BUILDER   Explicit buildx builder name. Required for every build; all
                    node endpoints must resolve to local Unix Docker contexts
                    and advertise every requested target platform.
  POLARDB_PUBLISH_PREFLIGHT_ONLY
                    Set to true with POLARDB_PUSH=true to validate every
                    release gate without invoking build or push.
  POLARDB_BUILD_PREFLIGHT_ONLY
                    Set to true to validate a local single-platform build
                    without invoking BuildKit.
  POLARDB_RELEASE   2.0.14 (default) or 2.0.16.
  SPILO_BASE_IMAGE and POLARDB_EXTRACTOR_IMAGE overrides are forbidden.
EOF
}

rpm_directory=${1:-}
release=${POLARDB_RELEASE:-2.0.14}
case "$release" in
    2.0.14)
        image=${2:-apecloud/polardb-pg:2.0.14.41.0-local}
        rpm_names=(
            PolarDB-2.0.14.41.0-20260421202048.alios7.x86_64.rpm
            PolarDB-2.0.14.41.0-20260421202048.alios7.aarch64.rpm
        )
        expected_sha256s=(
            c7ba1f7470d5ac946d8a5029081b930c5b379358cd65a2bf843a021e405df553
            51dee31bd859086c465dec532e616061c83950b3f2626c69a075fbcd85f01622
        )
        pinned_spilo_base_image=apecloud/spilo:14.23@sha256:e6b514f0b79f8beba3183fd1e1e1070d27d8948032c89944738c8a0f0407dafe
        dockerfile=postgres-appliance/Dockerfile.polardb-pg
        image_tag=2.0.14.41.0
        ;;
    2.0.16)
        image=${2:-apecloud/polardb-pg:2.0.16.17.0-local}
        rpm_names=(
            PolarDB16-2.0.16.17.0-20260519173021.al8.x86_64.rpm
            PolarDB16-2.0.16.17.0-20260519173021.al8.aarch64.rpm
        )
        expected_sha256s=(
            afa962176695179bf20641364c78c2536451d2d4046c7e8bbcb222fb49097a35
            c05a10970eacb0ffa98c2e09868d2561ac4efd5c5471c362eba36f7a80702b04
        )
        pinned_spilo_base_image=apecloud/spilo:16.14@sha256:b8522b0bbbfd6d08a1aee3c03f61ff427c7ce6938e15f03d78b2955fd7a981e9
        dockerfile=postgres-appliance/Dockerfile.polardb-pg16
        image_tag=2.0.16.17.0
        ;;
    *) echo "unsupported POLARDB_RELEASE: $release" >&2; exit 1 ;;
esac

if [[ -z "$rpm_directory" ]]; then
    usage >&2
    exit 2
fi
if [[ ! -d "$rpm_directory" ]]; then
    echo "RPM directory does not exist: $rpm_directory" >&2
    exit 1
fi

platform=${PLATFORM:-}
if [[ -z "$platform" ]]; then
    case "$(uname -m)" in
        x86_64) platform=linux/amd64 ;;
        arm64|aarch64) platform=linux/arm64 ;;
        *)
            echo "unsupported local architecture: $(uname -m)" >&2
            exit 1
            ;;
    esac
fi

case "$platform" in
    linux/amd64|linux/arm64|linux/amd64,linux/arm64|linux/arm64,linux/amd64) ;;
    *)
        echo "unsupported PLATFORM: $platform; expected linux/amd64, linux/arm64, or linux/amd64,linux/arm64" >&2
        exit 1
        ;;
esac

expected_entries=$(printf '%s\n' "${rpm_names[@]}" | LC_ALL=C sort)
actual_entries=$(find "$rpm_directory" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)
if [[ "$actual_entries" != "$expected_entries" ]]; then
    echo "RPM directory must contain exactly the two pinned vendor packages and no other entries" >&2
    echo "expected:" >&2
    printf '  %s\n' "${rpm_names[@]}" >&2
    echo "observed entries:" >&2
    sed 's/^/  /' <<<"${actual_entries:-<empty>}" >&2
    exit 1
fi

for rpm_index in "${!rpm_names[@]}"; do
    rpm_path=$rpm_directory/${rpm_names[$rpm_index]}
    expected_sha256=${expected_sha256s[$rpm_index]}
    if [[ ! -f "$rpm_path" || -L "$rpm_path" ]]; then
        echo "pinned RPM is missing, not a regular file, or is a symlink: $rpm_path" >&2
        exit 1
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        actual_sha256=$(sha256sum "$rpm_path" | awk '{print $1}')
    else
        actual_sha256=$(shasum -a 256 "$rpm_path" | awk '{print $1}')
    fi
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        echo "SHA256 mismatch for $rpm_path" >&2
        echo "expected: $expected_sha256" >&2
        echo "actual:   $actual_sha256" >&2
        exit 1
    fi
done

publish=${POLARDB_PUSH:-false}
preflight_only=${POLARDB_PUBLISH_PREFLIGHT_ONLY:-false}
build_preflight_only=${POLARDB_BUILD_PREFLIGHT_ONLY:-false}
builder=${POLARDB_BUILDER:-}
[[ -n "$builder" ]] \
    || { echo "every build requires an explicit POLARDB_BUILDER" >&2; exit 1; }
builder_args=(--builder "$builder")
pinned_extractor_image=ubuntu:22.04@sha256:2edbbc5dc405e9612ba3584ce95480277e3eb374407b5505fe26f17df77c7dbc
[[ -z "${SPILO_BASE_IMAGE+x}" ]] \
    || { echo "SPILO_BASE_IMAGE overrides are forbidden for proprietary RPM builds" >&2; exit 1; }
[[ -z "${POLARDB_EXTRACTOR_IMAGE+x}" ]] \
    || { echo "POLARDB_EXTRACTOR_IMAGE overrides are forbidden for proprietary RPM builds" >&2; exit 1; }
spilo_base_image=$pinned_spilo_base_image
extractor_image=$pinned_extractor_image

[[ -z "${DOCKER_HOST:-}" || "$DOCKER_HOST" == unix://* ]] \
    || { echo "refusing a non-local DOCKER_HOST: $DOCKER_HOST" >&2; exit 1; }
builder_inspect=$(docker buildx inspect "$builder" --bootstrap) \
    || { echo "cannot inspect the selected buildx builder: $builder" >&2; exit 1; }
builder_driver=$(awk '$1 == "Driver:" {print $2; exit}' <<<"$builder_inspect")
[[ "$builder_driver" == docker-container ]] \
    || { echo "proprietary RPM builds require a dedicated docker-container buildx driver, got: ${builder_driver:-unknown}" >&2; exit 1; }
builder_endpoints=()
while IFS= read -r builder_endpoint; do
    builder_endpoints+=("$builder_endpoint")
done < <(awk '$1 == "Endpoint:" {print $2}' <<<"$builder_inspect")
((${#builder_endpoints[@]} > 0)) || { echo "builder has no inspectable node endpoints: $builder" >&2; exit 1; }
for builder_endpoint in "${builder_endpoints[@]}"; do
    if [[ "$builder_endpoint" == unix://* ]]; then
        docker_endpoint=$builder_endpoint
    else
        docker_endpoint=$(docker context inspect "$builder_endpoint" --format '{{.Endpoints.docker.Host}}') \
            || { echo "builder node endpoint is not a Docker context: $builder_endpoint" >&2; exit 1; }
    fi
    [[ "$docker_endpoint" == unix://* ]] \
        || { echo "builder node is not bound to a local Unix Docker endpoint: $builder_endpoint -> $docker_endpoint" >&2; exit 1; }
    echo "trusted builder node: builder=$builder driver=$builder_driver endpoint=$builder_endpoint docker_host=$docker_endpoint"
done
builder_platforms=$(awk '$1 == "Platforms:" {sub(/^[^:]*:[[:space:]]*/, ""); print}' <<<"$builder_inspect" \
    | tr ',' '\n' | sed 's/[[:space:]*]//g')
while IFS= read -r requested_platform; do
    [[ -n "$requested_platform" ]] || continue
    grep -Fxq "$requested_platform" <<<"$builder_platforms" \
        || { echo "builder does not advertise $requested_platform: $builder" >&2; exit 1; }
done < <(tr ',' '\n' <<<"$platform")

case "$publish" in
    false)
        [[ "$preflight_only" == false ]] \
            || { echo "POLARDB_PUBLISH_PREFLIGHT_ONLY=true requires POLARDB_PUSH=true" >&2; exit 1; }
        [[ "$build_preflight_only" == false || "$build_preflight_only" == true ]] \
            || { echo "invalid POLARDB_BUILD_PREFLIGHT_ONLY: $build_preflight_only; expected true or false" >&2; exit 1; }
        output_args=(--load)
        ;;
    true)
        [[ "$preflight_only" == false || "$preflight_only" == true ]] \
            || { echo "invalid POLARDB_PUBLISH_PREFLIGHT_ONLY: $preflight_only; expected true or false" >&2; exit 1; }
        [[ "$build_preflight_only" == false ]] \
            || { echo "POLARDB_BUILD_PREFLIGHT_ONLY=true cannot be combined with POLARDB_PUSH=true" >&2; exit 1; }
        [[ "$platform" == linux/amd64,linux/arm64 || "$platform" == linux/arm64,linux/amd64 ]] \
            || { echo "POLARDB_PUSH=true requires PLATFORM=linux/amd64,linux/arm64" >&2; exit 1; }
        [[ -n "${2:-}" ]] || { echo "POLARDB_PUSH=true requires an explicit private registry image" >&2; exit 1; }
        case "$image" in
            apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/polardb-pg:"$image_tag" | \
            apecloud-registry-vpc.cn-zhangjiakou.cr.aliyuncs.com/apecloud/polardb-pg:"$image_tag")
                ;;
            *)
                echo "refusing publish target outside the approved private ACR repository: $image" >&2
                exit 1
                ;;
        esac
        [[ "${POLARDB_PRIVATE_REPOSITORY_CONFIRMED:-false}" == true ]] \
            || { echo "publishing requires POLARDB_PRIVATE_REPOSITORY_CONFIRMED=true after an independent privacy check" >&2; exit 1; }
        [[ "${POLARDB_TRUSTED_BUILDER_CONFIRMED:-false}" == true ]] \
            || { echo "publishing requires POLARDB_TRUSTED_BUILDER_CONFIRMED=true after checking the local builder" >&2; exit 1; }
        output_args=(--push)
        ;;
    *)
        echo "invalid POLARDB_PUSH: $publish; expected true or false" >&2
        exit 1
        ;;
esac

if [[ "$publish" == false && "$platform" == *,* ]]; then
    echo "multi-architecture builds require POLARDB_PUSH=true because Docker cannot --load a manifest list" >&2
    exit 1
fi

[[ "${POLARDB_DEDICATED_BUILDER_CONFIRMED:-false}" == true ]] \
    || { echo "building requires POLARDB_DEDICATED_BUILDER_CONFIRMED=true because the selected builder cache will be pruned" >&2; exit 1; }

if [[ "$preflight_only" == true || "$build_preflight_only" == true ]]; then
    echo "PolarDB-PG build preflight passed for $image on builder $builder (publish=$publish)"
    exit 0
fi

cleanup_required=false
cleanup_builder_cache() {
    [[ "$cleanup_required" == true ]] || return 0
    docker buildx prune --builder "$builder" --all --force >/dev/null \
        || echo "WARNING: failed to prune dedicated builder cache for $builder; remove it before treating the RPM input as locally cleaned" >&2
}
trap cleanup_builder_cache EXIT
cleanup_required=true
build_status=0
docker buildx build \
    "${builder_args[@]}" \
    --platform "$platform" \
    --build-context "polardb_rpms=$rpm_directory" \
    --file "$dockerfile" \
    --build-arg "SPILO_BASE_IMAGE=$spilo_base_image" \
    --build-arg "POLARDB_EXTRACTOR_IMAGE=$extractor_image" \
    --tag "$image" \
    "${output_args[@]}" \
    postgres-appliance || build_status=$?

if docker buildx prune --builder "$builder" --all --force >/dev/null; then
    cleanup_required=false
else
    echo "failed to prune dedicated builder cache for $builder" >&2
    exit 1
fi
((build_status == 0)) || exit "$build_status"

echo "built $image for $platform (push=$publish)"
