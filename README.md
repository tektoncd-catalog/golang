# Golang Tasks for Tekton

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/golang)](https://artifacthub.io/packages/search?repo=golang)

This repository contains verified Tekton Tasks for building and testing Go projects.

## Tasks

| Task | Description |
|------|-------------|
| [`golang-build`](task/golang-build/) | Build Go packages |
| [`golang-test`](task/golang-test/) | Run Go tests |

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

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.
