# PolarDB-PG image

`Dockerfile.polardb-pg` overlays the vendor PolarDB-PG 2.0.14.41.0 payload on
the pinned multi-architecture `apecloud/spilo:14.23` runtime. It keeps Spilo and
Patroni's PostgreSQL 14 process-management contract while resolving
`/usr/lib/postgresql/14/bin` to `/u01/polardb_pg/bin`.

`Dockerfile.polardb-pg16` uses the vendor `PolarDB16` 2.0.16.17.0 AL8 RPMs
on pinned `apecloud/spilo:16.14`. Their binaries report PostgreSQL 16.13
(PolarDB 16.13.17.0), live under `/u01/polardb_pg_16`, and replace
`/usr/lib/postgresql/16/bin`. This RPM accepts ordinary `initdb` but does not
accept the older `-m pg|ora` initialization option; the 16 image supports
`pg` mode only and rejects `ora`.

The vendor RPMs are proprietary external build inputs. Do not add them to Git.
The build requires the directory to contain exactly the two pinned RPMs and no
other entries. It passes that exact directory as one read-only BuildKit named
context, selects one package from `TARGETARCH`, checks the source-controlled
SHA256, and extracts only its archive payload. It does not run RPM `%pre`,
`%post`, or trigger scriptlets, and every build step after the RPM context is
mounted is network disabled. The RPM archives are mounted only for the extractor
step and are not retained in image layers. Every build, including a local
`--load`, requires an explicit dedicated `docker-container` builder whose nodes
resolve to local Unix-socket Docker contexts; remote builders and the shared
Docker Engine `docker` driver are forbidden. BuildKit secret mounts cannot
carry these RPMs because the active builder limits each secret to 500 KiB. The
selected builder must therefore be dedicated to this task and its cache is
pruned after every real build. Base and extractor image overrides are also
rejected for every proprietary RPM build.
The RPM archive is not copied into the final image, but its extracted proprietary
runtime payload is necessarily present in the image that is pushed. Both the Spilo
runtime and Ubuntu extractor image are pinned by multi-architecture digest, and
release publishing rejects overrides. The extractor still resolves
`libarchive-tools` from the pinned Ubuntu release repository before the RPM is
mounted, so a release build must also retain the build log/package version as
supply-chain evidence.

## Build

From the repository root on an ARM64 workstation:

```bash
POLARDB_BUILDER=polardb-local \
POLARDB_DEDICATED_BUILDER_CONFIRMED=true \
hack/build-polardb-pg.sh \
  /Users/ldm/Documents/misc/polardb \
  apecloud/polardb-pg:2.0.14.41.0-local
```

For an explicit local platform, set `PLATFORM=linux/arm64` or
`PLATFORM=linux/amd64`.

For the 2.0.16 image, place only the two verified `PolarDB16-*.al8` RPMs in a
separate directory, set `POLARDB_RELEASE=2.0.16`, and use the
`2.0.16.17.0` image tag. The same builder, SHA256, local-endpoint, and private
publish checks apply. Run `test_polardb_pg16_image.sh` against each locally
built architecture before considering publication. The supplied AliOS 7 RPMs
report the same PostgreSQL 16.13 kernel but are not used by this image.

Publishing is fail-closed to the complete AMD64 and ARM64 pair and to the selected
release's exact Alibaba Cloud ACR `apecloud/polardb-pg` tag. Independently verify
that the repository is private before setting the confirmation gate and running:

```bash
POLARDB_PUSH=true \
POLARDB_PRIVATE_REPOSITORY_CONFIRMED=true \
POLARDB_TRUSTED_BUILDER_CONFIRMED=true \
POLARDB_DEDICATED_BUILDER_CONFIRMED=true \
POLARDB_BUILDER=polardb-local \
PLATFORM=linux/amd64,linux/arm64 \
hack/build-polardb-pg.sh \
  /Users/ldm/Documents/misc/polardb \
  apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/polardb-pg:2.0.14.41.0
```

For 2.0.16, set `POLARDB_RELEASE=2.0.16`, use the verified AL8 RPM directory,
and replace the target tag with `2.0.16.17.0`.

BuildKit selects the matching RPM independently for each target architecture
and publishes one manifest list. A release must verify both platform manifests
and their digests after the push. It must also prove that an authenticated pull
succeeds and an anonymous pull is denied. The VPC registry hostname is allowed
for an authorized runner in that network; use the public hostname shown above
when the VPC endpoint is not resolvable.

`POLARDB_BUILDER` must name an explicitly prepared local buildx builder for all
builds. The script inspects that exact builder, verifies every builder node maps
to a Unix-socket Docker context, verifies every requested target platform, and
passes the same name to `docker buildx build --builder`. A remote builder is
forbidden because it would receive the proprietary named-context input. The
confirmation flag acknowledges that this builder is dedicated and that its
entire unused cache will be pruned after the build. If a build is forcibly killed
before cleanup completes, run `docker buildx prune --builder polardb-local
--all --force` before treating the local RPM staging data as cleaned.

Before the real push, the same command can be checked without invoking a build
or registry write by adding `POLARDB_PUBLISH_PREFLIGHT_ONLY=true`.
For a local single-platform build, use `POLARDB_BUILD_PREFLIGHT_ONLY=true` to
run the RPM, builder, endpoint, pinned-image, and platform gates without
invoking BuildKit.

The equivalent direct BuildKit contract is:

```bash
docker buildx build \
  --builder polardb-local \
  --platform linux/arm64 \
  --build-context polardb_rpms=/absolute/path/to/the-two-verified-rpms \
  --file postgres-appliance/Dockerfile.polardb-pg \
  --tag apecloud/polardb-pg:2.0.14.41.0-local \
  --load \
  postgres-appliance
```

## Runtime defaults

- `LD_LIBRARY_PATH=/u01/polardb_pg/lib` keeps the AliOS-built binaries on their
  packaged libraries.
- `PGVERSION=14` and `/usr/lib/postgresql/14/bin` preserve Patroni's binary
  discovery contract. The packaged `pg_basebackup` symlink resolves to
  `polar_basebackup`.
- `POLARDB_COMPATIBILITY_MODE` accepts `pg` (default) or `ora` and is appended to
  Patroni's `bootstrap.initdb` options.
- Stock Spilo's PGDG `shared_preload_libraries` defaults are disabled. Explicit
  caller values are preserved, but must only name extensions built for this
  PolarDB-PG kernel.
- The recommended PolarDB defaults
  `polar_worker.enable_standby_wal_prealloc=off` and
  `polar_resource_manager.enable_resource_manager=off` are added only to
  bootstrap DCS parameters unless explicitly overridden. They must not be
  copied into Patroni's local parameters, because local values override later
  dynamic DCS updates from KubeBlocks parameter reconfiguration.

The current RPM is license-enabled: the reported supplier contract is unrestricted
operation for 30 days without a license, followed by throttling to 20 maximum
connections. That policy is not implemented or bypassed by this image and must be
covered by product licensing and acceptance work.

## Smoke test

```bash
DOCKER_DEFAULT_PLATFORM=linux/amd64 \
postgres-appliance/tests/test_polardb_pg_image.sh \
  apecloud/polardb-pg:2.0.14.41.0-local
```

Omit `DOCKER_DEFAULT_PLATFORM` for a native build, or set it to the platform of
the image when smoke-testing through emulation.

The smoke checks the executable and library wiring, the `polar_basebackup` link,
Patroni version detection, both `initdb -m pg` and `initdb -m ora`, and the normal
`configure_spilo.py all` configuration path. HA replication, failover, Ganos, Oracle SQL/JDBC behavior,
backup/restore, and license expiry require later deployed-product tests.
