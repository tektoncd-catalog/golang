# Golang Goimports (StepAction)

This StepAction checks that Go source code is formatted and imports are
organized using [goimports](https://pkg.go.dev/golang.org/x/tools/cmd/goimports).
It is a superset of `gofmt` — it also groups and sorts import statements.
It is a StepAction-only tool, designed to be composed with other steps.

## Installation

```bash
kubectl apply -f https://raw.githubusercontent.com/tektoncd-catalog/golang/main/stepaction/golang-goimports/golang-goimports.yaml
```

> Requires Tekton Pipelines with StepActions enabled (`enable-step-actions: "true"`).

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `source-path` | Path to the Go source code to operate on | _(required)_ |
| `paths` | Paths to check for formatting | `.` |
| `skip-dirs` | Directories to exclude (pipe-separated regex) | `vendor` |
| `goimports-version` | Version of goimports to install | `latest` |
| `version` | Golang version to use | `1.26` |

> Installs `goimports` at runtime via `go install`, so the step needs network
> access to the Go module proxy.

## Platforms

The StepAction can be run on `linux/amd64`, `linux/arm64`, `linux/s390x`, and `linux/ppc64le` platforms.

## Usage

```yaml
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: imports-check
spec:
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: my-source
  taskSpec:
    workspaces:
      - name: source
    steps:
      - name: goimports
        ref:
          name: golang-goimports
        params:
          - name: source-path
            value: $(workspaces.source.path)
```

## gofmt vs goimports

Use `golang-fmt` if your project only enforces formatting. Use
`golang-goimports` if your project also enforces import grouping/ordering
(most Go projects do). Do not use both — goimports is a strict superset.
