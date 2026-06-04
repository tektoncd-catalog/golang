#!/usr/bin/env bash

# Copyright 2024 The Tekton Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# E2e test for Tekton Bundle publishing.
# Pushes the golang tasks as bundles to ttl.sh, then runs PipelineRuns
# that reference them via the bundle resolver.
#
# Environment variables:
#   PIPELINE_VERSION  - Tekton Pipelines version to install (default: v1.12.0)
#   TIMEOUT           - Timeout for PipelineRun (default: 300s)
#   BUNDLE_REGISTRY   - Registry to push bundles to (default: ttl.sh)

set -euo pipefail

PIPELINE_VERSION="${PIPELINE_VERSION:-v1.12.0}"
TIMEOUT="${TIMEOUT:-300s}"
BUNDLE_REGISTRY="${BUNDLE_REGISTRY:-ttl.sh}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Generate unique bundle references (ttl.sh images expire after 1h)
BUNDLE_ID="golang-e2e-$(head -c 8 /proc/sys/kernel/random/uuid)"
BUILD_BUNDLE_REF="${BUNDLE_REGISTRY}/${BUNDLE_ID}-build:1h"
TEST_BUNDLE_REF="${BUNDLE_REGISTRY}/${BUNDLE_ID}-test:1h"

echo "--- Installing Tekton Pipelines ${PIPELINE_VERSION}"
kubectl apply --filename "https://github.com/tektoncd/pipeline/releases/download/${PIPELINE_VERSION}/release.yaml"
echo "--- Waiting for Tekton Pipelines to be ready"
kubectl wait --for=condition=available --timeout=120s deployment/tekton-pipelines-controller -n tekton-pipelines
kubectl wait --for=condition=available --timeout=120s deployment/tekton-pipelines-webhook -n tekton-pipelines

echo "--- Installing git-clone task"
kubectl apply -f "https://raw.githubusercontent.com/tektoncd-catalog/git-clone/v1.4.0/task/git-clone/git-clone.yaml"

echo "--- Pushing Tekton Bundles"
echo "    golang-build -> ${BUILD_BUNDLE_REF}"
tkn bundle push "${BUILD_BUNDLE_REF}" -f "${ROOT_DIR}/task/golang-build/golang-build.yaml"
echo "    golang-test  -> ${TEST_BUNDLE_REF}"
tkn bundle push "${TEST_BUNDLE_REF}" -f "${ROOT_DIR}/task/golang-test/golang-test.yaml"

echo "--- Creating PipelineRuns using bundle resolver"
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: golang-build-bundle-test
spec:
  pipelineSpec:
    workspaces:
      - name: shared-workspace
    tasks:
      - name: fetch-source
        taskRef:
          name: git-clone
        workspaces:
          - name: output
            workspace: shared-workspace
        params:
          - name: url
            value: https://github.com/google/uuid
      - name: build
        runAfter: ["fetch-source"]
        taskRef:
          resolver: bundles
          params:
            - name: bundle
              value: ${BUILD_BUNDLE_REF}
            - name: name
              value: golang-build
            - name: kind
              value: task
        workspaces:
          - name: source
            workspace: shared-workspace
        params:
          - name: package
            value: github.com/google/uuid
          - name: packages
            value: "./..."
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 256Mi
---
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: golang-test-bundle-test
spec:
  pipelineSpec:
    workspaces:
      - name: shared-workspace
    tasks:
      - name: fetch-source
        taskRef:
          name: git-clone
        workspaces:
          - name: output
            workspace: shared-workspace
        params:
          - name: url
            value: https://github.com/google/uuid
      - name: test
        runAfter: ["fetch-source"]
        taskRef:
          resolver: bundles
          params:
            - name: bundle
              value: ${TEST_BUNDLE_REF}
            - name: name
              value: golang-test
            - name: kind
              value: task
        workspaces:
          - name: source
            workspace: shared-workspace
        params:
          - name: package
            value: github.com/google/uuid
          - name: packages
            value: "./..."
          - name: flags
            value: "-v"
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 256Mi
EOF

FAILED=0
PASSED=0

echo "--- Waiting for PipelineRuns to complete (timeout: ${TIMEOUT})"
for pr in golang-build-bundle-test golang-test-bundle-test; do
    echo -n "  ${pr} ... "
    if kubectl wait --for=condition=Succeeded --timeout="${TIMEOUT}" pipelinerun/"${pr}" 2>/dev/null; then
        echo "PASSED"
        PASSED=$((PASSED + 1))
    else
        echo "FAILED"
        kubectl get pipelinerun/"${pr}" -o jsonpath='{.status.conditions[*].message}' 2>/dev/null || true
        echo ""
        for pod in $(kubectl get pods -l tekton.dev/pipelineRun="${pr}" -o name 2>/dev/null); do
            echo "  >> ${pod}"
            kubectl logs "${pod}" --all-containers 2>/dev/null || true
        done
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=== Results: ${PASSED}/2 passed, ${FAILED} failed ==="

if [[ ${FAILED} -gt 0 ]]; then
    exit 1
fi
