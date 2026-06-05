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

# E2e test runner for the golang StepActions.
# Installs the default (Debian) StepActions and runs a composition Pipeline
# that uses golang-fmt, golang-vet, golang-build and golang-test as steps in
# a single Task — exercising the composable StepAction workflow.
#
# Environment variables:
#   PIPELINE_VERSION  - Tekton Pipelines version to install (default: v1.12.0)
#   TIMEOUT           - Timeout for the PipelineRun (default: 300s)

set -euo pipefail

PIPELINE_VERSION="${PIPELINE_VERSION:-v1.12.0}"
TIMEOUT="${TIMEOUT:-300s}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "--- Installing Tekton Pipelines ${PIPELINE_VERSION}"
kubectl apply --filename "https://github.com/tektoncd/pipeline/releases/download/${PIPELINE_VERSION}/release.yaml"
echo "--- Waiting for Tekton Pipelines to be ready"
kubectl wait --for=condition=available --timeout=120s deployment/tekton-pipelines-controller -n tekton-pipelines
kubectl wait --for=condition=available --timeout=120s deployment/tekton-pipelines-webhook -n tekton-pipelines

echo "--- Enabling StepActions (enable-step-actions)"
kubectl patch configmap feature-flags -n tekton-pipelines \
    --type merge -p '{"data":{"enable-step-actions":"true"}}'

echo "--- Installing git-clone task"
kubectl apply -f "https://raw.githubusercontent.com/tektoncd-catalog/git-clone/v1.6.0/task/git-clone/git-clone.yaml"

echo "--- Installing golang StepActions (default/Debian variants)"
for sadir in "${ROOT_DIR}"/stepaction/*/; do
    name="$(basename "${sadir}")"
    # Only the default (non-alpine) variants for the smoke test.
    [[ "${name}" == *-alpine ]] && continue
    f="${sadir}${name}.yaml"
    [[ -f "${f}" ]] || continue
    echo "    Applying ${f}"
    kubectl apply -f "${f}"
done

echo "--- Applying StepAction composition test"
# Use 'create' for the PipelineRun (uses generateName for idempotency),
# but 'apply' for the Pipeline definition.
kubectl apply -f <(yq 'select(.kind == "Pipeline")' "${ROOT_DIR}/test/stepactions/composition.yaml")
kubectl create -f <(yq 'select(.kind == "PipelineRun")' "${ROOT_DIR}/test/stepactions/composition.yaml")

sleep 5

PIPELINERUNS=$(kubectl get pipelinerun -o name | sed 's|pipelinerun.tekton.dev/||')

FAILED=0
PASSED=0
TOTAL=0

echo "--- Waiting for PipelineRuns to complete (timeout: ${TIMEOUT})"
for pr in ${PIPELINERUNS}; do
    TOTAL=$((TOTAL + 1))
    echo -n "  ${pr} ... "
    if kubectl wait --for=condition=Succeeded --timeout="${TIMEOUT}" pipelinerun/"${pr}" 2>/dev/null; then
        echo "PASSED"
        PASSED=$((PASSED + 1))
    else
        echo "FAILED"
        kubectl get pipelinerun/"${pr}" -o jsonpath='{.status.conditions[*].message}' 2>/dev/null || true
        echo ""
        kubectl get taskrun -l tekton.dev/pipelineRun="${pr}" \
            -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[0].reason,MESSAGE:.status.conditions[0].message' 2>/dev/null || true
        for pod in $(kubectl get pods -l tekton.dev/pipelineRun="${pr}" -o name 2>/dev/null); do
            echo "  >> ${pod}"
            kubectl logs "${pod}" --all-containers 2>/dev/null || true
        done
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=== Results: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="

if [[ ${FAILED} -gt 0 ]]; then
    exit 1
fi
