# AGENTS.md

Guidance for AI coding agents working in `tektoncd-catalog/golang`. For full
detail see [DEVELOPMENT.md](DEVELOPMENT.md).

## Repository structure

| Path | Role |
|------|------|
| `base/*.yaml` | **Edit these.** Hand-maintained templates (one per tool), version-agnostic, with `IMAGE_PLACEHOLDER`. |
| `catalog.yaml` | Manifest: which tools to generate, which kinds (`task`/`stepaction`), and the variants. Single source of truth for *what* is produced. |
| `VERSION` | Single source of truth for the version (injected as `app.kubernetes.io/version`). |
| `hack/generate.sh` | Generator: `base/` + `catalog.yaml` + `VERSION` → `task/` + `stepaction/`. |
| `hack/generate-stepaction.py` | Derives a StepAction from a generated Task. |
| `hack/release.sh` | Release automation. |
| `task/`, `stepaction/` | **Generated — never edit by hand.** |
| `test/` | e2e runners (`e2e-tests.sh`, `e2e-tests-alpine.sh`, `e2e-stepactions.sh`, `e2e-bundle-test.sh`). |
| `.github/workflows/` | `build.yaml` (lint/verify/e2e), `release.yaml` (bundle publish). |

## Critical Rules

1. **Never edit `task/` or `stepaction/` directly.** They are generated. Edit
   `base/` and/or `catalog.yaml`, then run `./hack/generate.sh`. CI's
   verify-generated step diffs committed files against freshly generated ones
   and fails on mismatch.
2. **No `$(params.*)` in StepAction `script:` blocks** — injection risk and not
   supported. Pass values via `env:` and reference the env var (e.g.
   `${SOURCE_PATH}`, `${PARAM_PATHS}`). Workspace refs in scripts become
   `${SOURCE_PATH}`; in `workingDir`/`env` values they become
   `$(params.source-path)`.
3. **Templates are version-agnostic.** The version lives only in the `VERSION`
   file and is injected as the `app.kubernetes.io/version` label at generation
   time. Never hardcode a version in `base/`.
4. **Sign off every commit** (DCO / EasyCLA): `git commit --signoff`.
5. **Use conventional commit prefixes** (`feat:`, `fix:`, `docs:`, `chore:`,
   `ci:`) — the release changelog is derived from them.

## Common commands

```bash
./hack/generate.sh                      # regenerate task/ + stepaction/
./hack/generate.sh my-catalog.yaml      # regenerate from a forked manifest
./hack/release.sh v1.3.0 --dry-run       # preview a release (restores the tree)
./hack/release.sh v1.3.0 --dry-run --llm # preview with gh copilot changelog
./test/e2e-tests.sh                     # e2e in a kind cluster (needs a cluster)
```

Generation needs `yq` (mikefarah) and either `uv` or a `python3` with PyYAML.

## Validating changes locally

1. After editing `base/`/`catalog.yaml`, run `./hack/generate.sh`.
2. Confirm `git status` shows only intended changes (clean verify-generated).
3. Run the relevant e2e script against a kind cluster.
4. Update `README.md` if you added a tool or variant.

## Common pitfalls

- Forgetting to run `./hack/generate.sh` after editing a template → CI
  verify-generated fails.
- Putting `$(params.*)` in a StepAction script → invalid; use env vars.
- Adding a version to a `base/` template → breaks determinism; versions come
  from `VERSION`.
- Editing a generated `README.md` for an `-alpine` variant → it's regenerated
  from the default tool's README; edit the default instead.
