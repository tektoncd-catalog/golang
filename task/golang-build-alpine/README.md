# Golang Build

This Task builds Go packages.

## Installation

```bash
kubectl apply -f https://raw.githubusercontent.com/tektoncd-catalog/golang/main/task/golang-build/golang-build.yaml
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `package` | Base package to build in | _(required)_ |
| `packages` | Packages to build | `./cmd/...` |
| `version` | Golang version to use for builds | `1.26` |
| `flags` | Flags to use for the build command | `-v` |
| `GOOS` | Target operating system | `linux` |
| `GOARCH` | Target architecture | `amd64` |
| `GO111MODULE` | Value of module support | `auto` |
| `GOCACHE` | Go caching directory path | `""` |
| `GOMODCACHE` | Go mod caching directory path | `""` |
| `CGO_ENABLED` | Toggle cgo tool during build. Use `0` to disable (for static builds). | `""` |
| `GOSUMDB` | Go checksum database URL. Use `off` to disable checksum validation. | `""` |

## Workspaces

| Workspace | Description | Optional |
|-----------|-------------|----------|
| `source` | The Go source code to build | No |

## Platforms

The Task can be run on `linux/amd64`, `linux/s390x`, and `linux/ppc64le` platforms.

Set the `GOARCH` parameter according to the desired target architecture.

## Usage

```yaml
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: build-my-code
spec:
  taskRef:
    name: golang-build
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: my-source
  params:
    - name: package
      value: github.com/tektoncd/pipeline
```

### Static binary build

```yaml
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: build-static-binary
spec:
  taskRef:
    name: golang-build
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: my-source
  params:
    - name: package
      value: github.com/my-org/my-project
    - name: flags
      value: -v -ldflags="-s -w"
    - name: CGO_ENABLED
      value: "0"
```
