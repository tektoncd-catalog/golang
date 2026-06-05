# Golang Fmt (StepAction)

This StepAction checks that Go source code is formatted with `gofmt` and fails
if any file needs formatting. It is a StepAction-only tool, designed to be
composed with other steps.

## Installation

```bash
kubectl apply -f https://raw.githubusercontent.com/tektoncd-catalog/golang/main/stepaction/golang-fmt/golang-fmt.yaml
```

> Requires Tekton Pipelines with StepActions enabled (`enable-step-actions: "true"`).

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `source-path` | Path to the Go source code to operate on | _(required)_ |
| `paths` | Paths to check for formatting | `.` |
| `version` | Golang version to use | `1.26` |

## Platforms

The StepAction can be run on `linux/amd64`, `linux/arm64`, `linux/s390x`, and `linux/ppc64le` platforms.

## Usage

```yaml
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: fmt-check
spec:
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: my-source
  taskSpec:
    workspaces:
      - name: source
    steps:
      - name: fmt
        ref:
          name: golang-fmt
        params:
          - name: source-path
            value: $(workspaces.source.path)
```
