# Govulncheck (StepAction)

This StepAction scans Go code for known vulnerabilities using
[govulncheck](https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck). It is a
StepAction-only tool, designed to be composed with other steps.

## Installation

```bash
kubectl apply -f https://raw.githubusercontent.com/tektoncd-catalog/golang/main/stepaction/govulncheck-alpine/govulncheck-alpine.yaml
```

> Requires Tekton Pipelines with StepActions enabled (`enable-step-actions: "true"`).

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `source-path` | Path to the Go source code to operate on | _(required)_ |
| `packages` | Packages to scan | `./...` |
| `govulncheck-version` | Version of govulncheck to install | `latest` |
| `version` | Golang version to use | `1.26` |

> Installs `govulncheck` at runtime via `go install`, so the step needs network
> access to the Go module proxy and the vulnerability database.

## Platforms

The StepAction can be run on `linux/amd64`, `linux/arm64`, `linux/s390x`, and `linux/ppc64le` platforms.

## Usage

```yaml
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: vuln-scan
spec:
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: my-source
  taskSpec:
    workspaces:
      - name: source
    steps:
      - name: govulncheck-alpine
        ref:
          name: govulncheck-alpine
        params:
          - name: source-path
            value: $(workspaces.source.path)
```
