# Golang Test (StepAction)

This StepAction runs Go tests. It is the StepAction form of the `golang-test`
Task, for composing into a single Task with other steps.

## Installation

```bash
kubectl apply -f https://raw.githubusercontent.com/tektoncd-catalog/golang/main/stepaction/golang-test/golang-test.yaml
```

> Requires Tekton Pipelines with StepActions enabled (`enable-step-actions: "true"`).

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `source-path` | Path to the Go source code to operate on | _(required)_ |
| `package` | Package (and its children) under test | _(required)_ |
| `packages` | Packages to test | `./...` |
| `context` | Path to the directory to use as context | `.` |
| `version` | Golang version to use for tests | `1.26` |
| `flags` | Flags to use for the test command | `-race -cover -v` |
| `GOOS` | Target operating system | `linux` |
| `GOARCH` | Target architecture | `amd64` |
| `GO111MODULE` | Value of module support | `auto` |
| `GOCACHE` | Go caching directory path | `""` |
| `GOMODCACHE` | Go mod caching directory path | `""` |

## Platforms

The StepAction can be run on `linux/amd64`, `linux/arm64`, `linux/s390x`, and `linux/ppc64le` platforms.

> **Note**: Do not use the `-race` flag on `linux/s390x` — it is not supported on that platform.

## Usage

```yaml
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: test-my-code
spec:
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: my-source
  taskSpec:
    workspaces:
      - name: source
    steps:
      - name: test
        ref:
          name: golang-test
        params:
          - name: source-path
            value: $(workspaces.source.path)
          - name: package
            value: github.com/my-org/my-project
```
