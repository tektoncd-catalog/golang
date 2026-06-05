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

# Release script for tektoncd-catalog/golang.
#
# Usage:
#   ./hack/release.sh v1.2.0              # bump VERSION, regenerate, commit, tag, push
#   ./hack/release.sh v1.2.0 --dry-run    # show what would change
#   ./hack/release.sh v1.2.0 --llm        # generate changelog with gh copilot
#
# Versioning: the VERSION file at the repo root is the single source of truth.
# This script bumps it and runs hack/generate.sh, which injects the version
# into the generated task files. Base templates stay version-agnostic.
#
# Signing: task YAMLs are NOT signed in-repo (tracked upstream:
# tektoncd/cli#2894 and tektoncd/cli#2895). Bundles are cosign-signed in the
# release workflow instead.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- Parse arguments ---
VERSION=""
DRY_RUN=false
USE_LLM=false

for arg in "$@"; do
    case "${arg}" in
        --dry-run) DRY_RUN=true ;;
        --llm) USE_LLM=true ;;
        v*) VERSION="${arg}" ;;
        *) echo "Unknown argument: ${arg}"; exit 1 ;;
    esac
done

if [[ -z "${VERSION}" ]]; then
    echo "Usage: $0 <version> [--dry-run] [--llm]"
    echo "  Example: $0 v1.2.0"
    exit 1
fi

# Check tkn CLI
if ! command -v tkn &>/dev/null; then
    echo "Error: tkn CLI not found. Install from https://tekton.dev/docs/cli/"
    exit 1
fi

# Validate version format
if ! echo "${VERSION}" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Error: version must match vX.Y.Z (got: ${VERSION})"
    exit 1
fi

# Strip the 'v' prefix for places that need bare version
BARE_VERSION="${VERSION#v}"

cd "${ROOT_DIR}"

# --- Task files to update (discover all golang-* tasks) ---
TASK_FILES=()
for taskdir in "${ROOT_DIR}"/task/golang-*; do
    task=$(basename "${taskdir}")
    TASK_FILES+=("task/${task}/${task}.yaml")
done

# --- Detect current version from the VERSION file (single source of truth) ---
CURRENT_VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
CURRENT_TAG="v${CURRENT_VERSION}"

echo "=== Release ${VERSION} ==="
echo "  Current: ${CURRENT_TAG}"
echo "  Target:  ${VERSION}"
echo ""

# --- Ensure we're on main and up to date (skip for dry-run) ---
BRANCH=$(git branch --show-current)
if [[ "${DRY_RUN}" != true ]]; then
    if [[ "${BRANCH}" != "main" ]]; then
        echo "Error: must be on main branch (currently on: ${BRANCH})"
        exit 1
    fi

    git fetch origin main
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/main)
    if [[ "${LOCAL}" != "${REMOTE}" ]]; then
        echo "Error: local main is not up to date with origin/main"
        echo "  Local:  ${LOCAL}"
        echo "  Remote: ${REMOTE}"
        echo "  Run: git pull origin main"
        exit 1
    fi
else
    git fetch origin main 2>/dev/null || true
fi

# --- Bump VERSION (single source of truth) and regenerate task files ---
echo "--- Bumping VERSION: ${CURRENT_VERSION} -> ${BARE_VERSION}"
echo "${BARE_VERSION}" > "${ROOT_DIR}/VERSION"
echo "--- Running hack/generate.sh to regenerate task and stepaction files at ${BARE_VERSION}..."
"${SCRIPT_DIR}/generate.sh"

# --- Generate changelog ---
echo "--- Commits since ${CURRENT_TAG}:"
COMMITS=$(git log --oneline "${CURRENT_TAG}..HEAD" --no-merges 2>/dev/null || git log --oneline -20)
echo "${COMMITS}"
echo ""

if [[ "${USE_LLM}" == true ]]; then
    echo "--- Generating changelog with gh copilot..."

    PROMPT="Generate a release changelog for version ${VERSION} of the tektoncd-catalog/golang project (Tekton Tasks for building and testing Go projects).

Here are the commits since the last release (${CURRENT_TAG}):

${COMMITS}

Output two sections:

1. An artifacthub.io/changes YAML annotation block (indented with 6 spaces) with entries like:
      - kind: added|changed|fixed|removed
        description: Short one-line description

2. A git tag annotation message with this format:
Release ${VERSION}

<category>:
- <description>

Use categories like Features, Fixes, Improvements, CI/Infra, Docs. Be concise.

Output the two sections separated by the exact string ---SEPARATOR--- on its own line."

    LLM_OUTPUT=$(gh copilot -p "${PROMPT}" 2>/dev/null || echo "")

    if [[ -n "${LLM_OUTPUT}" ]]; then
        AH_CHANGES=$(echo "${LLM_OUTPUT}" | sed -n '/^ *- kind:/,/---SEPARATOR---/p' | grep -v '^---SEPARATOR---')
        TAG_MESSAGE=$(echo "${LLM_OUTPUT}" | sed -n '/^---SEPARATOR---$/,$ p' | tail -n +2 | sed '/^$/d; /^[[:space:]]*$/d' | sed '1{/^$/d}')
    else
        echo "Warning: gh copilot not available, falling back to git log"
        USE_LLM=false
    fi
fi

if [[ "${USE_LLM}" != true ]]; then
    # Generate simple changelog from commit types
    AH_CHANGES=""
    while IFS= read -r line; do
        msg="${line#* }"  # strip commit hash
        case "${msg}" in
            feat:*|feat\(*) AH_CHANGES="${AH_CHANGES}      - kind: added\n        description: ${msg#*: }\n" ;;
            fix:*|fix\(*)   AH_CHANGES="${AH_CHANGES}      - kind: fixed\n        description: ${msg#*: }\n" ;;
            chore:*|ci:*|build*) AH_CHANGES="${AH_CHANGES}      - kind: changed\n        description: ${msg#*: }\n" ;;
            docs:*)         AH_CHANGES="${AH_CHANGES}      - kind: changed\n        description: ${msg#*: }\n" ;;
            *)              AH_CHANGES="${AH_CHANGES}      - kind: changed\n        description: ${msg}\n" ;;
        esac
    done <<< "${COMMITS}"

    TAG_MESSAGE="Release ${VERSION}

Changes since ${CURRENT_TAG}:
$(echo "${COMMITS}" | sed 's/^[a-f0-9]* /- /')"
fi

echo ""
echo "--- Artifact Hub changelog:"
echo -e "${AH_CHANGES}"
echo ""
echo "--- Tag message:"
echo "${TAG_MESSAGE}"
echo ""

# --- Files that change at release time ---
# Discover generated task and stepaction files plus the VERSION marker.
STEPACTION_FILES=()
for sadir in "${ROOT_DIR}"/stepaction/*/; do
    sa=$(basename "${sadir}")
    [[ -f "${sadir}${sa}.yaml" ]] && STEPACTION_FILES+=("stepaction/${sa}/${sa}.yaml")
done
ALL_FILES=("${TASK_FILES[@]}" "${STEPACTION_FILES[@]}" "VERSION")

echo "--- Files to commit:"
for f in "${ALL_FILES[@]}"; do
    echo "  ${f}"
done
echo ""

if [[ "${DRY_RUN}" == true ]]; then
    echo "--- Dry run: showing changes ---"
    git --no-pager diff -- VERSION task/ stepaction/ || true
    echo ""
    echo "--- Restoring working tree (dry run) ---"
    git checkout -- VERSION task/ stepaction/ 2>/dev/null || true
    echo "Dry run complete. Run without --dry-run to apply."
    exit 0
fi

echo "--- Committing..."
git add VERSION task/ stepaction/
git commit --signoff --message "chore: bump version to ${VERSION}"

echo "--- Pushing to main..."
git push origin main:main

echo "--- Tagging ${VERSION}..."
git tag -a "${VERSION}" -m "${TAG_MESSAGE}"

echo "--- Pushing tag..."
git push origin "refs/tags/${VERSION}:refs/tags/${VERSION}"

echo ""
echo "=== Release ${VERSION} initiated ==="
echo "  Monitor: gh run list --workflow=release.yaml --limit 1"
echo "  View:    https://github.com/tektoncd-catalog/golang/releases/tag/${VERSION}"
