# Golang Test

This Task runs Go tests.

## Installation

```bash
kubectl apply -f https://raw.githubusercontent.com/tektoncd-catalog/golang/main/task/golang-test-alpine/golang-test-alpine.yaml
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `package` | Base package under test | _(required)_ |
| `packages` | Packages to test | `./...` |
| `context` | Path to the directory to use as context | `.` |
| `version` | Golang version to use for tests | `1.26` |
| `flags` | Flags to use for the test command | `-race -cover -v` |
| `GOOS` | Target operating system | `linux` |
| `GOARCH` | Target architecture | `amd64` |
| `GO111MODULE` | Value of module support | `auto` |
| `GOCACHE` | Go caching directory path | `""` |
| `GOMODCACHE` | Go mod caching directory path | `""` |

## Workspaces

| Workspace | Description | Optional |
|-----------|-------------|----------|
| `source` | The Go source code to test | No |

## Platforms

The Task can be run on `linux/amd64`, `linux/s390x`, and `linux/ppc64le` platforms.

Set the `GOARCH` parameter according to the desired target architecture.

> **Note**: Do not use the `-race` flag on `linux/s390x` — it is not supported on that platform.

## Usage

```yaml
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: test-my-code
spec:
  taskRef:
    name: golang-test-alpine
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: my-source
  params:
    - name: package
      value: github.com/tektoncd/pipeline
```

### Test specific packages

```yaml
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: test-specific-packages
spec:
  taskRef:
    name: golang-test-alpine
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: my-source
  params:
    - name: package
      value: github.com/tektoncd/pipeline
    - name: packages
      value: ./pkg/reconciler/...
    - name: flags
      value: -race -cover -v -count=1
```
