# Golang Build (StepAction)

This StepAction builds Go packages. It is the StepAction form of the
`golang-build` Task, for composing into a single Task with other steps.

## Installation

```bash
kubectl apply -f https://raw.githubusercontent.com/tektoncd-catalog/golang/main/stepaction/golang-build/golang-build.yaml
```

> Requires Tekton Pipelines with StepActions enabled (`enable-step-actions: "true"`).

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `source-path` | Path to the Go source code to operate on | _(required)_ |
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

## Platforms

The StepAction can be run on `linux/amd64`, `linux/arm64`, `linux/s390x`, and `linux/ppc64le` platforms.

## Usage

Compose with other steps in a single Task:

```yaml
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: build-my-code
spec:
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: my-source
  taskSpec:
    workspaces:
      - name: source
    steps:
      - name: build
        ref:
          name: golang-build
        params:
          - name: source-path
            value: $(workspaces.source.path)
          - name: package
            value: github.com/my-org/my-project
```
