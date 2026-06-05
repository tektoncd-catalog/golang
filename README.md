# Golang Tasks for Tekton

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/golang)](https://artifacthub.io/packages/search?repo=golang)

This repository contains verified Tekton Tasks and StepActions for building and testing Go projects.

## Tasks

| Task | Description | Default Go version |
|--------------------|-------------|--------------------|
| [`golang-build`](task/golang-build/) | Build Go packages | 1.26 |
| [`golang-build-alpine`](task/golang-build-alpine/) | Build Go packages (Alpine) | 1.26 |
| [`golang-test`](task/golang-test/) | Run Go tests | 1.26 |
| [`golang-test-alpine`](task/golang-test-alpine/) | Run Go tests (Alpine) | 1.26 |

## StepActions

[StepActions](https://tekton.dev/docs/pipelines/stepactions/) are composable
steps you can combine into a single Task — e.g. `git-clone` + `golang-fmt` +
`golang-vet` + `golang-build` + `golang-test`. Each StepAction is also
available in Debian (default) and Alpine variants.

| StepAction | Description | Task equivalent |
|------------|-------------|-----------------|
| [`golang-build`](stepaction/golang-build/) | Build Go packages | ✅ |
| [`golang-test`](stepaction/golang-test/) | Run Go tests | ✅ |
| [`golang-fmt`](stepaction/golang-fmt/) | Check formatting (`gofmt -l`) | StepAction-only |
| [`golang-vet`](stepaction/golang-vet/) | Static analysis (`go vet`) | StepAction-only |
| [`golang-fix`](stepaction/golang-fix/) | Modernize code (`go fix`, Go 1.26+) | StepAction-only |
| [`govulncheck`](stepaction/govulncheck/) | Vulnerability scanning | StepAction-only |

StepActions require Tekton Pipelines with `enable-step-actions: "true"`. The
source code is passed via the `source-path` param (instead of a workspace).

```yaml
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: go-ci
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
        ref: { name: golang-fmt }
        params:
          - name: source-path
            value: $(workspaces.source.path)
      - name: build
        ref: { name: golang-build }
        params:
          - name: source-path
            value: $(workspaces.source.path)
          - name: package
            value: github.com/my-org/my-project
```


## Variants

Each task is available in two variants:

| Task | Variant | Image |
|------|---------|-------|
| `golang-build` | Debian (default) | `golang:1.26` |
| `golang-build-alpine` | Alpine | `golang:1.26-alpine` |
| `golang-test` | Debian (default) | `golang:1.26` |
| `golang-test-alpine` | Alpine | `golang:1.26-alpine` |

The **Debian** variant is the default and is recommended for most use cases.
The **Alpine** variant produces a smaller footprint and is opt-in.

To install an Alpine variant:

```bash
kubectl apply -f https://raw.githubusercontent.com/tektoncd-catalog/golang/main/task/golang-build-alpine/golang-build-alpine.yaml
kubectl apply -f https://raw.githubusercontent.com/tektoncd-catalog/golang/main/task/golang-test-alpine/golang-test-alpine.yaml
```

## Installation

Install both tasks:

```bash
kubectl apply -f https://raw.githubusercontent.com/tektoncd-catalog/golang/main/task/golang-build/golang-build.yaml
kubectl apply -f https://raw.githubusercontent.com/tektoncd-catalog/golang/main/task/golang-test/golang-test.yaml
```

## Quick Start

### Build

```yaml
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  generateName: golang-build-run-
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

### Test

```yaml
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  generateName: golang-test-run-
spec:
  taskRef:
    name: golang-test
  workspaces:
    - name: source
      persistentVolumeClaim:
        claimName: my-source
  params:
    - name: package
      value: github.com/tektoncd/pipeline
```

### Build and Test Pipeline

```yaml
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: golang-pipeline-run-
spec:
  pipelineSpec:
    workspaces:
      - name: shared-data
    params:
      - name: package
        type: string
    tasks:
      - name: fetch-source
        taskRef:
          name: git-clone
        workspaces:
          - name: output
            workspace: shared-data
        params:
          - name: url
            value: https://github.com/tektoncd/pipeline
      - name: build
        runAfter: ["fetch-source"]
        taskRef:
          name: golang-build
        workspaces:
          - name: source
            workspace: shared-data
        params:
          - name: package
            value: $(params.package)
      - name: test
        runAfter: ["fetch-source"]
        taskRef:
          name: golang-test
        workspaces:
          - name: source
            workspace: shared-data
        params:
          - name: package
            value: $(params.package)
  params:
    - name: package
      value: github.com/tektoncd/pipeline
  workspaces:
    - name: shared-data
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Gi
```

## Requirements

- Tekton Pipelines **v1.0.0** or later

## Versioning

These tasks pin a **default Go minor version** (e.g. `1.26`) rather than using `latest`.
This ensures reproducible builds — the same task definition produces consistent results
over time. Docker's minor tags (e.g. `golang:1.26`) still receive patch updates
automatically, so you get security fixes without behavior changes.

### Version scheme

| Task version | Default Go version | Notes |
|--------------|-------------------|-------|
| 1.1.0 | 1.26 | Current |
| 1.0.0 | latest | Initial release |

When a new Go minor version is released (e.g. 1.27), the task version is bumped
(e.g. 1.0.0 → 1.1.0) and the default is updated.

### Overriding the Go version

You can always override the default by setting the `version` parameter:

```yaml
params:
  - name: version
    value: "1.25"    # use a different minor version
  # or
  - name: version
    value: "1.26.4"  # pin to an exact patch version
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.
