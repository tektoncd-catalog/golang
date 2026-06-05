# Golang Vet (StepAction)

This StepAction runs `go vet` to report likely mistakes in Go source code. It
is a StepAction-only tool, designed to be composed with other steps.

## Installation

```bash
kubectl apply -f https://raw.githubusercontent.com/tektoncd-catalog/golang/main/stepaction/golang-vet-alpine/golang-vet-alpine.yaml
```

> Requires Tekton Pipelines with StepActions enabled (`enable-step-actions: "true"`).

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `source-path` | Path to the Go source code to operate on | _(required)_ |
| `packages` | Packages to vet | `./...` |
| `flags` | Additional flags to pass to `go vet` | `""` |
| `version` | Golang version to use | `1.26` |

## Platforms

The StepAction can be run on `linux/amd64`, `linux/arm64`, `linux/s390x`, and `linux/ppc64le` platforms.

## Usage

```yaml
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: vet-check
spec:
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: my-source
  taskSpec:
    workspaces:
      - name: source
    steps:
      - name: vet
        ref:
          name: golang-vet-alpine
        params:
          - name: source-path
            value: $(workspaces.source.path)
```
