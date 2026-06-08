# Contributing

Thanks for your interest in contributing to `tektoncd-catalog/golang`! This
repository is part of the Tekton Catalog and follows the broader
[tektoncd-catalog contributing guide](https://github.com/tektoncd-catalog/.github/blob/main/CONTRIBUTING.md).

For technical details on how the repo is structured and generated, see
[DEVELOPMENT.md](DEVELOPMENT.md).

## Developer Certificate of Origin (DCO)

All commits must be signed off to certify the
[Developer Certificate of Origin](https://developercertificate.org/). Add a
`Signed-off-by` trailer to every commit:

```bash
git commit --signoff -m "feat: add golang-lint StepAction"
```

The sign-off line must match the author's name and email. CI rejects PRs with
unsigned commits.

## Pull request workflow

1. **Fork and branch** from `main`.
2. **Edit `base/` templates and/or `catalog.yaml`** — never edit the generated
   files under `task/` or `stepaction/` directly.
3. **Regenerate** and commit the output:
   ```bash
   ./hack/generate.sh
   git add base/ catalog.yaml task/ stepaction/
   ```
4. **Test locally** (see [DEVELOPMENT.md](DEVELOPMENT.md#running-tests-locally)).
5. **Use conventional commit messages** (`feat:`, `fix:`, `docs:`, `chore:`,
   `ci:`) — the release changelog is derived from these prefixes.
6. **Open a PR** with a clear description.

Approvals are managed via `OWNERS` (Prow-based auto-merge).

## CI expectations

Every PR runs `.github/workflows/build.yaml`, which must pass:

- **Lint / verify-generated** — runs `./hack/generate.sh` and fails if the
  committed `task/`/`stepaction/` files differ from freshly generated ones
  (ignoring the `tekton.dev/signature` and `artifacthub.io/changes`
  annotations). If this fails, run `./hack/generate.sh` and commit the result.
- **Validate YAMLs** — checks `apiVersion`/`kind`/`metadata.name` for every
  Task (`tekton.dev/v1`) and StepAction (`tekton.dev/v1beta1`).
- **E2E matrix** — runs the e2e suites in a kind cluster across the supported
  Tekton Pipelines LTS versions, plus Alpine and StepAction suites.

> [!TIP]
> Before pushing, run `./hack/generate.sh` and make sure `git status` is clean
> (apart from your intended changes). This is the most common CI failure.

## Code of conduct

This project follows the Tekton
[Code of Conduct](code-of-conduct.md).
