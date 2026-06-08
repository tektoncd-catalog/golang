# Development

This document explains how the `tektoncd-catalog/golang` repository is
structured and how to develop, generate, test, and release its Tasks and
StepActions.

> [!IMPORTANT]
> The files under `task/` and `stepaction/` are **generated**. Never edit them
> directly. Edit the templates under `base/` (and `catalog.yaml`) and run
> `./hack/generate.sh`.

## Architecture overview

The repository uses a small generation framework so that a single source of
truth (the `base/` templates) produces every Task, StepAction, and variant.

```
base/*.yaml ──┐
catalog.yaml ─┼─► hack/generate.sh ──► task/<name>/<name>.yaml
VERSION ──────┘            │           stepaction/<name>/<name>.yaml
                           └─► hack/generate-stepaction.py (Task → StepAction)
```

Key files:

| Path | Role |
|------|------|
| `base/*.yaml` | Hand-edited template for each tool (`kind: Task` or `kind: StepAction`), version-agnostic, with `IMAGE_PLACEHOLDER` for the image. |
| `catalog.yaml` | Manifest: the single source of truth for *what* gets generated — the list of tools, which kinds (`task`, `stepaction`) each produces, and the variants (Debian + Alpine). |
| `VERSION` | Single source of truth for the version. Injected as the `app.kubernetes.io/version` label at generation time. |
| `hack/generate.sh` | The generator. Renders templates per variant and injects version/image/suffixes. |
| `hack/generate-stepaction.py` | Derives a StepAction from a generated Task (workspace → `source-path` param). |
| `hack/release.sh` | Release automation: bump `VERSION` → regenerate → inject Artifact Hub changelog → commit → tag → push. |
| `task/`, `stepaction/` | **Generated output.** Do not edit. |
| `test/` | e2e test runners and fixtures. |

### Why generation?

- **Deterministic:** CI regenerates the files and diffs them against what's
  committed (`verify-generated`). The committed files must match exactly.
- **DRY:** Debian and Alpine variants share one template; a StepAction is
  derived from its Task rather than maintained by hand.
- **Version-agnostic templates:** `base/` never mentions a version; it's
  injected from `VERSION`, so a version bump is just regeneration.

## How generation works

Run:

```bash
./hack/generate.sh                 # uses catalog.yaml
./hack/generate.sh my-catalog.yaml # use a forked manifest
```

Requirements: [`yq`](https://github.com/mikefarah/yq) (mikefarah's Go
implementation), and either [`uv`](https://github.com/astral-sh/uv) or a
`python3` with PyYAML available (for StepAction derivation).

For each tool in `catalog.yaml`, the generator reads `base/<name>.yaml` and,
for each variant:

1. **Renders the variant** with `render_with_variant`, which:
   - substitutes the variant's image (replacing `IMAGE_PLACEHOLDER`),
   - sets `metadata.name` (`<name>` or `<name>-alpine`),
   - injects the `app.kubernetes.io/version` label from `VERSION`,
   - appends the variant's `description_suffix` to `.spec.description`,
   - appends a display-name suffix (e.g. ` (alpine)`).
2. **Emits the Task** to `task/<obj_name>/<obj_name>.yaml` when `task` is in the
   tool's `generate:` list and the base is `kind: Task`.
3. **Derives the StepAction** when `stepaction` is requested:
   - if the base is `kind: Task`, runs `generate-stepaction.py` on the
     rendered Task;
   - if the base is `kind: StepAction`, renders it directly.
4. **Generates variant READMEs** from the default tool's README (rewriting
   names and paths).

### StepAction derivation (`generate-stepaction.py`)

The golang Tasks are single-step and use a single `source` workspace, so
deriving a StepAction is mechanical:

- The `source` workspace becomes a `source-path` **param**.
- `workingDir` and `env` value fields: `$(workspaces.source.path)` →
  `$(params.source-path)`.
- **Scripts:** `$(workspaces.source.path)` → `${SOURCE_PATH}`, because
  `$(params.*)` substitution is **not allowed in StepAction scripts**. A
  `SOURCE_PATH` env var (value `$(params.source-path)`) is injected so the
  script can reference it.
- Descriptions are reworded ("This Task" → "This StepAction").
- The `tekton.dev/signature` annotation is dropped.

## Adding a new tool

1. Create `base/<tool>.yaml`. Use `kind: Task` if it should also be a Task, or
   `kind: StepAction` for StepAction-only tools. Use `IMAGE_PLACEHOLDER` for
   the image. Keep it version-agnostic (no version in labels).
2. Add an entry to `catalog.yaml` under `tools:`:
   ```yaml
   - name: <tool>
     generate: [task, stepaction]   # or just [stepaction]
   ```
3. Regenerate and review:
   ```bash
   ./hack/generate.sh
   git status
   ```
4. Add e2e coverage under `test/` if applicable, and update `README.md`.

### Tip: StepAction script constraints

`$(params.*)` is **not** allowed inside StepAction `script:` blocks. Pass
parameters into the script via `env:` and reference the env var instead. The
golang StepActions follow this pattern (e.g. `PARAM_PATHS`, `SKIP_DIRS`,
`SOURCE_PATH`).

## Adding a new variant

Variants apply to every tool. Add an entry to `catalog.yaml` under `variants:`:

```yaml
variants:
  - suffix: ""                                          # default (Debian)
    image: "docker.io/library/golang:$(params.version)"
    description_suffix: ""
  - suffix: "-alpine"
    image: "docker.io/library/golang:$(params.version)-alpine"
    description_suffix: " Uses the Alpine-based Go image for smaller footprint."
```

Then run `./hack/generate.sh` and commit the new generated artifacts.

## Running tests locally

E2e tests run against a real Tekton install in a local
[kind](https://kind.sigs.k8s.io/) cluster.

```bash
# Create a cluster (or use the helm/kind-action equivalent locally)
kind create cluster

# Tasks (Debian)
./test/e2e-tests.sh

# Alpine variants
./test/e2e-tests-alpine.sh

# StepActions
./test/e2e-stepactions.sh

# Bundles
./test/e2e-bundle-test.sh
```

Useful environment variables:

| Var | Default | Meaning |
|-----|---------|---------|
| `PIPELINE_VERSION` | `v1.12.0` | Tekton Pipelines release to install |
| `TIMEOUT` | `300s` | Per-PipelineRun timeout |

CI runs the e2e suite across the supported Tekton Pipelines LTS versions (see
`.github/workflows/build.yaml`).

## Release process

Releases are driven by `hack/release.sh`:

```bash
./hack/release.sh v1.3.0 --dry-run        # preview the diff, restores the tree
./hack/release.sh v1.3.0 --dry-run --llm  # preview with gh copilot changelog
./hack/release.sh v1.3.0                   # bump, regenerate, commit, tag, push
```

What it does:

1. Validates the version (`vX.Y.Z`) and that you're on an up-to-date `main`.
2. Writes the bare version to `VERSION` and runs `hack/generate.sh`.
3. Builds a changelog (from conventional-commit prefixes, or via `gh copilot`
   with `--llm`).
4. Injects an `artifacthub.io/changes` annotation into every generated YAML.
5. Commits (`--signoff`), pushes `main`, creates an annotated tag, and pushes
   the tag.

The tag push triggers `.github/workflows/release.yaml`, which publishes
cosign-signed Tekton bundles to GHCR.

> [!NOTE]
> Task YAMLs are **not** signed in-repo (tracked upstream in
> tektoncd/cli#2894 and tektoncd/cli#2895). Bundles are cosign-signed in the
> release workflow instead.

## Downstream usage

Downstream consumers can fork the manifest and point the generator at it to
produce the same catalog with custom images:

```bash
cp catalog.yaml my-catalog.yaml
# edit variant images to your registry
./hack/generate.sh my-catalog.yaml
```

## See also

- [CONTRIBUTING.md](CONTRIBUTING.md) — contribution workflow and CI expectations.
- [AGENTS.md](AGENTS.md) — quick reference for AI coding agents.
