#!/usr/bin/env python3

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

"""Derive a StepAction YAML from a generated golang Task YAML.

The golang tasks are single-step and use a single `source` workspace, so the
derivation is simpler than git-clone's: the `source` workspace becomes a
`source-path` param, and references to `$(workspaces.source.path)` are
rewritten to `$(params.source-path)`. The golang tasks produce no results.

Usage: generate-stepaction.py <task.yaml> <stepaction.yaml>

Requires PyYAML. Invoke via: uv run --with pyyaml python3 hack/generate-stepaction.py ...
"""

import copy
import re
import sys

import yaml

# Workspace → param mapping for golang tasks.
SOURCE_PARAM = {
    "name": "source-path",
    "description": "Path to the Go source code to operate on.",
    "type": "string",
}

WORKSPACE_PATH_REF = "$(workspaces.source.path)"
PARAM_PATH_REF = "$(params.source-path)"


class StepActionDumper(yaml.SafeDumper):
    pass


def str_representer(dumper, data):
    if "\n" in data:
        return dumper.represent_scalar("tag:yaml.org,2002:str", data, style="|")
    if data == "" or re.match(r"^[\d.]+$", data):
        return dumper.represent_scalar("tag:yaml.org,2002:str", data, style='"')
    if data.lower() in ("true", "false", "yes", "no"):
        return dumper.represent_scalar("tag:yaml.org,2002:str", data, style='"')
    return dumper.represent_scalar("tag:yaml.org,2002:str", data)


StepActionDumper.add_representer(str, str_representer)


def transform_description(desc: str) -> str:
    d = desc
    d = d.replace("This Task is Golang task to", "This StepAction is a Golang step to")
    d = d.replace("this Task", "this StepAction")
    d = d.replace("This Task", "This StepAction")
    return d


def rewrite_workspace_refs(text: str) -> str:
    return text.replace(WORKSPACE_PATH_REF, PARAM_PATH_REF)


def generate(task_file: str, output_file: str) -> None:
    with open(task_file) as f:
        task = yaml.safe_load(f)

    meta = task["metadata"]
    spec = task["spec"]
    step = spec["steps"][0]

    sa = {
        "apiVersion": "tekton.dev/v1beta1",
        "kind": "StepAction",
        "metadata": {
            "name": meta["name"],
            "labels": {
                "app.kubernetes.io/version": meta.get("labels", {}).get(
                    "app.kubernetes.io/version", "0.1"
                ),
            },
            "annotations": {},
        },
        "spec": {},
    }

    # Copy annotations (skip any signature).
    for k, v in meta.get("annotations", {}).items():
        if k == "tekton.dev/signature":
            continue
        sa["metadata"]["annotations"][k] = v

    sa["spec"]["description"] = transform_description(spec.get("description", ""))

    # Params: source-path replaces the workspace, then the task's own params.
    sa["spec"]["params"] = [copy.deepcopy(SOURCE_PARAM)]
    for p in spec.get("params", []):
        p2 = copy.deepcopy(p)
        if "description" in p2 and isinstance(p2["description"], str):
            p2["description"] = p2["description"].replace("this Task", "this StepAction")
        sa["spec"]["params"].append(p2)

    sa["spec"]["image"] = step["image"]

    if "workingDir" in step:
        sa["spec"]["workingDir"] = rewrite_workspace_refs(step["workingDir"])

    if "env" in step:
        sa["spec"]["env"] = copy.deepcopy(step["env"])

    if "securityContext" in step:
        sa["spec"]["securityContext"] = copy.deepcopy(step["securityContext"])

    sa["spec"]["script"] = rewrite_workspace_refs(step.get("script", ""))

    header = (
        f"# Generated from task/{meta['name']}/{meta['name']}.yaml \u2014 do not edit directly.\n"
    )

    with open(output_file, "w") as f:
        f.write(header)
        yaml.dump(
            sa,
            f,
            Dumper=StepActionDumper,
            default_flow_style=False,
            allow_unicode=True,
            sort_keys=False,
        )


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <task.yaml> <stepaction.yaml>", file=sys.stderr)
        sys.exit(1)
    generate(sys.argv[1], sys.argv[2])
