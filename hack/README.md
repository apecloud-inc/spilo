# Hack Scripts

This directory contains utility scripts for building and testing the spilo-init image.

## Scripts

### `build-init-image.sh`

Full-featured build script with multiple options for building the spilo-init Docker image.

#### Usage

```bash
# Quick local build for testing
./hack/build-init-image.sh --single-platform --test

# Build and push with custom tag
./hack/build-init-image.sh -t v1.0.0 --push

# Build for specific registry
./hack/build-init-image.sh -r myregistry.com/myorg -t latest --push

# Multi-platform build and push
./hack/build-init-image.sh -t v1.0.0 --push
```

#### Options

- `-r, --registry`: Docker registry (default: apecloud)
- `-n, --name`: Image name (default: spilo-init)
- `-t, --tag`: Image tag (default: latest)
- `-p, --platform`: Target platform (default: linux/amd64,linux/arm64)
- `--push`: Push image to registry after build
- `--test`: Run tests after build
- `--single-platform`: Build for current platform only (faster for testing)
- `-h, --help`: Show help message

### `quick-build.sh`

Simple script for quick local development builds.

#### Usage

```bash
# Quick build for local testing
./hack/quick-build.sh
```

This script:
- Builds the image as `apecloud/spilo-init:dev`
- Only builds for current platform (faster)
- Runs a quick file structure test

## Examples

### Local Development Workflow

```bash
# 1. Quick build during development
./hack/quick-build.sh

# 2. Full test when ready
./hack/build-init-image.sh --single-platform --test

# 3. Multi-platform build and push for release
./hack/build-init-image.sh -t v1.2.3 --push
```

### CI/CD Pipeline

```bash
# Build and push with automatic tag
./hack/build-init-image.sh -t ${CI_COMMIT_TAG:-latest} --push
```

## Image Contents

The spilo-init image contains:

- `/spilo-init/bin/wal-g` - WAL-G binary from apecloud/wal-g:postgres-1.2
- `/spilo-init/scripts/` - All spilo scripts (bootstrap, major_upgrade, etc.)
- `/spilo-init/launch.sh` - Launch script
- **Complete shell environment**: Ubuntu 22.04 base with bash and all standard utilities

## Usage as Init Container

Use this image as an init container and manually copy the files you need:

```yaml
apiVersion: v1
kind: Pod
spec:
  initContainers:
  - name: copy-spilo-files
    image: apecloud/spilo-init:latest
    command: ['sh', '-c']
    args:
    - |
      echo "Copying spilo files to shared volume..."
      mkdir -p /spilo/bin /spilo/scripts
      cp -r /spilo-init/scripts/* /spilo/scripts/
      cp /spilo-init/launch.sh /spilo/
      cp /spilo-init/bin/wal-g /spilo/bin/
      chmod +x /spilo/bin/wal-g /spilo/launch.sh
      echo "Files copied successfully!"
    volumeMounts:
    - name: spilo-volume
      mountPath: /spilo
  containers:
  - name: postgres
    image: postgres:15
    volumeMounts:
    - name: spilo-volume
      mountPath: /spilo
  volumes:
  - name: spilo-volume
    emptyDir: {}
```

Or copy only specific files you need:

```yaml
# Copy only wal-g binary
args:
- |
  mkdir -p /spilo/bin
  cp /spilo-init/bin/wal-g /spilo/bin/
  chmod +x /spilo/bin/wal-g

# Copy only scripts
args:
- |
  mkdir -p /spilo/scripts
  cp -r /spilo-init/scripts/* /spilo/scripts/
```

After the init container runs, the PostgreSQL container will have access to the copied files in `/spilo/`.

## Script Execution Support

The image uses Ubuntu 22.04 as the base, which includes a complete shell environment with bash and all standard utilities. You can execute scripts directly within the init container:

### Running bash scripts (recommended)

```yaml
# Execute bash scripts directly
args:
- |
  # Copy files first
  mkdir -p /spilo/bin /spilo/scripts
  cp -r /spilo-init/scripts/* /spilo/scripts/
  cp /spilo-init/bin/wal-g /spilo/bin/
  chmod +x /spilo/bin/wal-g

  # Execute bash scripts natively
  bash /spilo-init/scripts/post_init.sh arg1 arg2

  # Or run scripts directly (shebang will be respected)
  /spilo-init/scripts/some-setup-script.sh
```

### Complete example with script execution

```yaml
apiVersion: v1
kind: Pod
spec:
  initContainers:
  - name: spilo-init
    image: apecloud/spilo-init:latest
    command: ['bash', '-c']
    args:
    - |
      echo "Starting spilo initialization..."

      # Copy files
      mkdir -p /spilo/bin /spilo/scripts
      cp -r /spilo-init/scripts/* /spilo/scripts/
      cp /spilo-init/bin/wal-g /spilo/bin/
      chmod +x /spilo/bin/wal-g

      # Run initialization script
      bash /spilo-init/scripts/post_init.sh postgres mydb

      echo "Spilo initialization completed!"
    volumeMounts:
    - name: spilo-volume
      mountPath: /spilo
```

### Available tools in the image:
- **Full Ubuntu 22.04 environment** with all standard utilities
- `bash` - Full bash shell with all features
- `coreutils` - Complete GNU coreutils
- `findutils` - GNU findutils
- All standard Linux utilities (grep, sed, awk, curl, etc.)

### Compatibility:
- ✅ **Full bash compatibility** - all bash scripts work natively
- ✅ **All shell features** - arrays, advanced tests, etc.
- ✅ **Standard utilities** - same environment as main spilo image
