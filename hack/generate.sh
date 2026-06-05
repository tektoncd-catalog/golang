#!/usr/bin/env bash
# Generates Task and StepAction YAML files from base/ templates, the catalog
# manifest, and the VERSION file.
#
# Usage: ./hack/generate.sh [catalog-file]
#   catalog-file: path to the catalog manifest (default: catalog.yaml in root)
#
# The catalog manifest lists each tool and the kinds to generate:
#   tools:
#     - name: golang-build
#       generate: [task, stepaction]   # Task base → Task + derived StepAction
#     - name: golang-fmt
#       generate: [stepaction]         # StepAction base → StepAction only
#   variants: [...]                    # applied to every generated artifact
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MANIFEST="${1:-${REPO_ROOT}/catalog.yaml}"

# Version is the single source of truth in the VERSION file at the repo root.
# It is injected into generated files as the app.kubernetes.io/version label,
# so base/ templates stay version-agnostic and generation stays deterministic
# (CI can reproduce the exact committed files).
VERSION_FILE="${REPO_ROOT}/VERSION"
if [[ ! -f "${VERSION_FILE}" ]]; then
  echo "Error: VERSION file not found: ${VERSION_FILE}" >&2
  exit 1
fi
VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"

if [[ ! -f "${MANIFEST}" ]]; then
  echo "Error: catalog manifest not found: ${MANIFEST}" >&2
  exit 1
fi

if ! command -v yq &>/dev/null; then
  echo "Error: yq (mikefarah/yq) is required but not found in PATH" >&2
  exit 1
fi

BASE_DIR="${REPO_ROOT}/base"
TASK_DIR="${REPO_ROOT}/task"
STEPACTION_DIR="${REPO_ROOT}/stepaction"

# Python runner for the StepAction derivation script. Prefer uv (pulls in
# PyYAML without polluting the system), fall back to a python3 that already
# has yaml available.
if command -v uv &>/dev/null; then
  PYRUN=(uv run --quiet --with pyyaml python3)
elif python3 -c 'import yaml' 2>/dev/null; then
  PYRUN=(python3)
else
  echo "Error: need either 'uv' or a python3 with PyYAML for StepAction derivation" >&2
  exit 1
fi

VARIANT_COUNT="$(yq '.variants | length' "${MANIFEST}")"
TOOL_COUNT="$(yq '.tools | length' "${MANIFEST}")"

# render_with_variant <base_file> <kind_path> <name> <image> <desc_suffix> <display_suffix>
# Emits a generated YAML (with header) to stdout: substitutes the image at the
# given path, sets the name, injects the version label, and appends the
# description/displayName suffixes.
render_with_variant() {
  local base_file="$1" image_path="$2" name="$3" image="$4" desc_suffix="$5" display_suffix="$6"
  local base_filename
  base_filename="$(basename "${base_file}")"
  printf '# Generated from base/%s \xe2\x80\x94 do not edit directly.\n' "${base_filename}"
  tail -n +2 "${base_file}" | yq eval \
    "${image_path} = \"${image}\" |
     .metadata.name = \"${name}\" |
     .metadata.labels[\"app.kubernetes.io/version\"] = \"${VERSION}\" |
     .spec.description = (.spec.description + \"${desc_suffix}\") |
     .metadata.annotations[\"tekton.dev/displayName\"] = (.metadata.annotations[\"tekton.dev/displayName\"] + \"${display_suffix}\")" \
    -
}

# variant_readme <default_dir> <variant_dir> <base_name> <obj_name> <path_prefix>
# Generates a variant README from the default tool's README, rewriting names
# and paths. No-op if the default README does not exist.
variant_readme() {
  local default_dir="$1" variant_dir="$2" base_name="$3" obj_name="$4" path_prefix="$5"
  if [[ -f "${default_dir}/README.md" ]]; then
    sed -e "s|${path_prefix}/${base_name}/${base_name}|${path_prefix}/${obj_name}/${obj_name}|g" \
        -e "s|name: ${base_name}|name: ${obj_name}|g" \
        "${default_dir}/README.md" > "${variant_dir}/README.md"
    echo "    Generated README.md from ${default_dir}/"
  fi
}

for t in $(seq 0 $((TOOL_COUNT - 1))); do
  name="$(yq ".tools[${t}].name" "${MANIFEST}")"
  mapfile -t modes < <(yq ".tools[${t}].generate[]" "${MANIFEST}")
  base_file="${BASE_DIR}/${name}.yaml"

  if [[ ! -f "${base_file}" ]]; then
    echo "Error: base template not found: ${base_file}" >&2
    exit 1
  fi

  base_kind="$(yq '.kind' "${base_file}")"
  echo "Processing tool: ${name} (kind=${base_kind}, generate=${modes[*]})"

  want_task=false
  want_stepaction=false
  for m in "${modes[@]}"; do
    [[ "${m}" == "task" ]] && want_task=true
    [[ "${m}" == "stepaction" ]] && want_stepaction=true
  done

  for i in $(seq 0 $((VARIANT_COUNT - 1))); do
    suffix="$(yq ".variants[${i}].suffix" "${MANIFEST}")"
    image="$(yq ".variants[${i}].image" "${MANIFEST}")"
    description_suffix="$(yq ".variants[${i}].description_suffix" "${MANIFEST}")"

    obj_name="${name}${suffix}"

    # Display-name suffix: "-alpine" → " (alpine)", "" → ""
    if [[ -n "${suffix}" ]]; then
      display_suffix=" (${suffix#-})"
    else
      display_suffix=""
    fi

    echo "  → ${obj_name}"

    if [[ "${base_kind}" == "Task" ]]; then
      # Render the Task variant (used for the task/ output and/or as the
      # source for StepAction derivation).
      task_dir="${TASK_DIR}/${obj_name}"
      task_file="${task_dir}/${obj_name}.yaml"
      mkdir -p "${task_dir}"
      render_with_variant "${base_file}" ".spec.steps[].image" \
        "${obj_name}" "${image}" "${description_suffix}" "${display_suffix}" > "${task_file}"

      if [[ "${want_task}" == true ]]; then
        [[ -n "${suffix}" ]] && variant_readme "${TASK_DIR}/${name}" "${task_dir}" "${name}" "${obj_name}" "task"
        echo "    Task: ${task_file}"
      fi

      if [[ "${want_stepaction}" == true ]]; then
        sa_dir="${STEPACTION_DIR}/${obj_name}"
        sa_file="${sa_dir}/${obj_name}.yaml"
        mkdir -p "${sa_dir}"
        "${PYRUN[@]}" "${SCRIPT_DIR}/generate-stepaction.py" "${task_file}" "${sa_file}"
        [[ -n "${suffix}" ]] && variant_readme "${STEPACTION_DIR}/${name}" "${sa_dir}" "${name}" "${obj_name}" "stepaction"
        echo "    StepAction (derived): ${sa_file}"
      fi

      # If task output is not wanted, drop the intermediate task file.
      if [[ "${want_task}" != true ]]; then
        rm -rf "${task_dir}"
      fi

    elif [[ "${base_kind}" == "StepAction" ]]; then
      if [[ "${want_stepaction}" == true ]]; then
        sa_dir="${STEPACTION_DIR}/${obj_name}"
        sa_file="${sa_dir}/${obj_name}.yaml"
        mkdir -p "${sa_dir}"
        render_with_variant "${base_file}" ".spec.image" \
          "${obj_name}" "${image}" "${description_suffix}" "${display_suffix}" > "${sa_file}"
        [[ -n "${suffix}" ]] && variant_readme "${STEPACTION_DIR}/${name}" "${sa_dir}" "${name}" "${obj_name}" "stepaction"
        echo "    StepAction: ${sa_file}"
      fi
    else
      echo "Error: unsupported base kind '${base_kind}' in ${base_file}" >&2
      exit 1
    fi
  done
done

echo "Done generating catalog artifacts."
