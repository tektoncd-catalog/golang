#!/usr/bin/env bash
# Generates task YAML files from base/ templates and variant definitions.
# Usage: ./hack/generate.sh [variants-file]
#   variants-file: path to variants YAML (default: variants.yaml in repo root)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VARIANTS_FILE="${1:-${REPO_ROOT}/variants.yaml}"

if [[ ! -f "${VARIANTS_FILE}" ]]; then
  echo "Error: variants file not found: ${VARIANTS_FILE}" >&2
  exit 1
fi

if ! command -v yq &>/dev/null; then
  echo "Error: yq (mikefarah/yq) is required but not found in PATH" >&2
  exit 1
fi

BASE_DIR="${REPO_ROOT}/base"
TASK_DIR="${REPO_ROOT}/task"

VARIANT_COUNT="$(yq '.variants | length' "${VARIANTS_FILE}")"

for base_file in "${BASE_DIR}"/*.yaml; do
  base_filename="$(basename "${base_file}")"
  base_name="${base_filename%.yaml}"

  echo "Processing base: ${base_name}"

  for i in $(seq 0 $((VARIANT_COUNT - 1))); do
    suffix="$(yq ".variants[${i}].suffix" "${VARIANTS_FILE}")"
    image="$(yq ".variants[${i}].image" "${VARIANTS_FILE}")"
    description_suffix="$(yq ".variants[${i}].description_suffix" "${VARIANTS_FILE}")"

    task_name="${base_name}${suffix}"
    task_dir="${TASK_DIR}/${task_name}"
    task_file="${task_dir}/${task_name}.yaml"

    echo "  → ${task_name}"

    # Create task dir if it doesn't exist
    mkdir -p "${task_dir}"

    # For non-default variants, seed OWNERS and generate README from the default
    # task dir, replacing task names and paths for the variant.
    if [[ -n "${suffix}" ]]; then
      default_dir="${TASK_DIR}/${base_name}"
      # Copy OWNERS as-is
      if [[ -f "${default_dir}/OWNERS" && ! -f "${task_dir}/OWNERS" ]]; then
        cp "${default_dir}/OWNERS" "${task_dir}/OWNERS"
        echo "    Copied OWNERS from ${default_dir}/"
      fi
      # Generate README with variant-specific names and paths
      if [[ -f "${default_dir}/README.md" ]]; then
        sed -e "s|task/${base_name}/${base_name}|task/${task_name}/${task_name}|g" \
            -e "s|name: ${base_name}|name: ${task_name}|g" \
            "${default_dir}/README.md" > "${task_dir}/README.md"
        echo "    Generated README.md from ${default_dir}/"
      fi
    fi

    # Build display-name suffix: "-alpine" → " (alpine)", "" → ""
    if [[ -n "${suffix}" ]]; then
      variant_label="${suffix#-}"
      display_suffix=" (${variant_label})"
    else
      display_suffix=""
    fi

    # Generate the task YAML:
    #  1. Strip the base template's header comment (first line).
    #  2. Pipe through yq to:
    #       - Replace IMAGE_PLACEHOLDER with the variant image.
    #       - Set metadata.name to the task name.
    #       - Append description_suffix to spec.description.
    #       - Append display_suffix to tekton.dev/displayName annotation.
    #  3. Prepend a "do not edit" header comment.
    {
      printf '# Generated from base/%s \xe2\x80\x94 do not edit directly.\n' "${base_filename}"
      tail -n +2 "${base_file}" | yq eval \
        ".spec.steps[].image = \"${image}\" |
         .metadata.name = \"${task_name}\" |
         .spec.description = (.spec.description + \"${description_suffix}\") |
         .metadata.annotations[\"tekton.dev/displayName\"] = (.metadata.annotations[\"tekton.dev/displayName\"] + \"${display_suffix}\")" \
        -
    } > "${task_file}"

    echo "    Written: ${task_file}"
  done
done

echo "Done generating task variants."
