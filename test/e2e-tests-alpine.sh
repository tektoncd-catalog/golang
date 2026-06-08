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

# E2e test runner for Alpine variants of golang-build and golang-test tasks.
# Installs the Alpine tasks, runs test PipelineRuns, and waits for completion.
#
# Environment variables:
#   PIPELINE_VERSION  - Tekton Pipelines version to install (default: v1.12.0)
#   TIMEOUT           - Timeout for each PipelineRun (default: 300s)

set -euo pipefail

PIPELINE_VERSION="${PIPELINE_VERSION:-v1.12.0}"
TIMEOUT="${TIMEOUT:-300s}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "--- Installing Tekton Pipelines ${PIPELINE_VERSION}"
kubectl apply --filename "https://github.com/tektoncd/pipeline/releases/download/${PIPELINE_VERSION}/release.yaml"
echo "--- Waiting for Tekton Pipelines to be ready"
# Wait for every control-plane deployment to be Available (cold kind nodes may
# still be pulling images), then wait for the admission webhook to actually
# have ready endpoints before applying any Tekton resources.
kubectl wait --for=condition=available --timeout=300s \
    deployment --all -n tekton-pipelines
echo "--- Waiting for the admission webhook to serve"
for _ in $(seq 1 30); do
    if [[ -n "$(kubectl get endpoints tekton-pipelines-webhook \
        -n tekton-pipelines -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)" ]]; then
        break
    fi
    sleep 5
done

echo "--- Installing git-clone task"
kubectl apply -f "https://raw.githubusercontent.com/tektoncd-catalog/git-clone/v1.6.0/task/git-clone/git-clone.yaml"

echo "--- Installing Alpine golang tasks"
kubectl apply -f "${ROOT_DIR}/task/golang-build-alpine/golang-build-alpine.yaml"
kubectl apply -f "${ROOT_DIR}/task/golang-test-alpine/golang-test-alpine.yaml"

echo "--- Creating test Pipelines and PipelineRuns"
for taskdir in "${ROOT_DIR}/task/golang-build-alpine/tests" "${ROOT_DIR}/task/golang-test-alpine/tests"; do
    for f in "${taskdir}"/*.yaml; do
        echo "    Applying ${f}"
        kubectl apply -f "${f}"
    done
done

# Wait a moment for resources to be picked up
sleep 5

# Collect all PipelineRun names
PIPELINERUNS=$(kubectl get pipelinerun -o name | sed 's|pipelinerun.tekton.dev/||')

FAILED=0
PASSED=0
TOTAL=0

# Snapshot each PipelineRun's spec (stripped of status and volatile metadata)
# so we can recreate it if it hits a transient flake. Dependency-free: kubectl
# -o yaml orders keys with status last, so cutting from `status:` to EOF is safe.
SNAP_DIR="$(mktemp -d)"
snapshot_run() {
    kubectl get pipelinerun/"$1" -o yaml --show-managed-fields=false 2>/dev/null \
        | sed -e '/^status:/,$d' \
              -e '/^  resourceVersion:/d' \
              -e '/^  uid:/d' \
              -e '/^  creationTimestamp:/d' \
              -e '/^  generation:/d' \
              -e '/^  selfLink:/d' \
        > "${SNAP_DIR}/$1.yaml"
}
for pr in ${PIPELINERUNS}; do
    snapshot_run "${pr}"
done

wait_for_run() {
    kubectl wait --for=condition=Succeeded --timeout="${TIMEOUT}" pipelinerun/"$1" 2>/dev/null
}

dump_run() {
    echo "  --- PipelineRun status ---"
    kubectl get pipelinerun/"$1" -o jsonpath='{.status.conditions[*].message}' 2>/dev/null || true
    echo ""
    echo "  --- TaskRun details ---"
    kubectl get taskrun -l tekton.dev/pipelineRun="$1" \
        -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[0].reason,MESSAGE:.status.conditions[0].message' 2>/dev/null || true
    echo ""
    echo "  --- Pod logs ---"
    for pod in $(kubectl get pods -l tekton.dev/pipelineRun="$1" -o name 2>/dev/null); do
        echo "  >> ${pod}"
        kubectl logs "${pod}" --all-containers 2>/dev/null || true
    done
    echo "  ---"
}

echo "--- Waiting for PipelineRuns to complete (timeout: ${TIMEOUT})"
for pr in ${PIPELINERUNS}; do
    TOTAL=$((TOTAL + 1))
    echo -n "  ${pr} ... "
    if wait_for_run "${pr}"; then
        echo "PASSED"
        PASSED=$((PASSED + 1))
        continue
    fi

    # Retry once: transient pod sandbox / network / image-pull blips on a
    # single-node kind cluster (many pods starting at once) can stall a pod
    # before its container ever runs. Recreate the PipelineRun from its
    # snapshot and wait again before declaring a real failure.
    echo -n "FLAKY, retrying ... "
    kubectl delete pipelinerun/"${pr}" --wait=true 2>/dev/null || true
    kubectl apply -f "${SNAP_DIR}/${pr}.yaml" >/dev/null 2>&1 || true
    if wait_for_run "${pr}"; then
        echo "PASSED"
        PASSED=$((PASSED + 1))
    else
        echo "FAILED"
        dump_run "${pr}"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=== Results: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="

if [[ ${FAILED} -gt 0 ]]; then
    exit 1
fi
