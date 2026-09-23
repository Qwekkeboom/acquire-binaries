# Plan: Repo improvements — version pinning, CI hygiene, docs

## Context

- All four build jobs now pass (run #21, commit `1ca6e61`): the `dissect.util._native` skip, macOS Xcode fix, draft-release job, and action bumps are all working.
- **The working tree has uncommitted action-version bumps** in `.github/workflows/binaries.yml` (checkout@v5 x4, cache@v5 x4, setup-python@v6 x2, upload-artifact@v5 x4, download-artifact@v5, ghaction-upx@v4, action-gh-release@v3). These are part of the desired final state — preserve them; do not revert.
- `pyoxidizer.bzl` uses only `VARS["flavor"]`; the `--var version` that all four jobs pass is ignored, and `acquire` is unpinned in `pip_args` — the binary embeds whatever acquire is latest on PyPI, so a `3.22` tag could ship acquire 3.23+.
- Plugin-list skew: the host install `pip install pyoxidizer dissect` resolves the dissect metapackage (3.20.1 → `dissect.target==3.23.1`), while the binary packages `dissect.target 3.25.1`. `plugin.generate()` (`dissect/target/plugin.py:1009`) **imports** every plugin module and records import failures as `FailureDescriptor`s — so the host env needs both the same target version and importable plugin deps.
- Workflow gaps: no `permissions:` block (every job gets ~15 write scopes), no `concurrency` group, no `workflow_dispatch`, no `.gitignore`, README has no release/limitation docs.

## Decisions

1. Pin acquire in the bzl via strict `VARS["version"]` (mirrors the `VARS["flavor"]` precedent; all jobs already pass `--var version`).
2. Host install becomes `pyoxidizer "acquire==${VERSION}" "dissect.target[full]"` — resolves the same target version as the packaged one and keeps all plugin deps importable. Not `acquire==X` alone (would shrink the plugin list) and not mirroring the full `pip_args` list (duplication; `[full]` is a superset).
3. Workflow-level `permissions: contents: read`; the release job keeps its own `contents: write`.
4. `concurrency` with `cancel-in-progress: true`, plus `workflow_dispatch`.
5. Dependabot for `github-actions`, weekly.
6. Deferred (per user): attestations, SHA-pinning actions, `dissect.util==3.24` pin, phantom-plugin cleanup.

## Tasks

**Task 1 — `pyoxidizer.bzl`: pin acquire to VERSION**
- In `pip_args`, change `"acquire",` to `"acquire==" + VARS["version"],`.
- Update the local-source comment (~line 43) to say: remove the **acquire pin** from pip_args when building from a local source directory.

**Task 2 — `binaries.yml`: align host install (4 edits)**
- build-linux-gnu: `/opt/python/cp39-cp39/bin/pip install pyoxidizer "acquire==${{ env.VERSION }}" "dissect.target[full]"`
- build-linux-musl: `/opt/python/cp39-cp39/bin/pip install "acquire==${{ env.VERSION }}" "dissect.target[full]"` (note: this job installs pyoxidizer via cargo, not pip)
- build-windows: `pip install pyoxidizer "acquire==${{ env.VERSION }}" "dissect.target[full]"`
- build-macos: `pip install pyoxidizer "acquire==${{ env.VERSION }}" "dissect.target[full]"`

**Task 3 — `binaries.yml`: top-level blocks**
- `on:` becomes:
  ```yaml
  on:
    push
    workflow_dispatch
  ```
- Add directly under `on:`:
  ```yaml
  concurrency:
    group: ${{ github.workflow }}-${{ github.ref }}
    cancel-in-progress: true
  ```
- Add after `env:`:
  ```yaml
  permissions:
    contents: read
  ```

**Task 4 — new file `.github/dependabot.yml`:**
  ```yaml
  version: 2
  updates:
    - package-ecosystem: github-actions
      directory: /
      schedule:
        interval: weekly
  ```

**Task 5 — new file `.gitignore`:**
  ```
  build/
  ```

**Task 6 — `README.md`: append two sections**
  ```markdown
  ## Releasing

  1. Bump `VERSION` in `.github/workflows/binaries.yml` to the acquire release to package.
  2. Commit and push to `main` (every push builds; only tags release).
  3. Tag the same number and push it: `git tag <VERSION> && git push origin <VERSION>`.
  4. After all four builds pass, a **draft** GitHub Release appears with the renamed
     binaries and a `SHA256SUMS` file. Review and publish it.

  ## Known limitations

  - `pycryptodome` is not packaged, so output encryption is unavailable.
  - The native Rust extensions of `dissect.util` (lz4/lzo decompression, crc32c) are
    excluded; the pure-Python fallbacks are used.
  - The Linux (musl) build uses the `esxi-compatibility` branch of fox-it's PyOxidizer fork.
  - Local builds require `pyoxidizer build ... --var flavor <flavor> --var version <X>`.
  ```

## Validation

1. **bzl pin** — local resolving test (as done previously):
   ```
   python3 -m venv /tmp/kilo/venv && /tmp/kilo/venv/bin/pip install pyoxidizer==0.24.0
   mkdir -p build/lib/dissect/target/plugins && printf '# placeholder\n' > build/lib/dissect/target/plugins/_pluginlist.py
   timeout 240 /tmp/kilo/venv/bin/pyoxidizer build --release --target-triple x86_64-unknown-linux-gnu --var flavor standalone --var version 3.22
   ```
   Success: the pip download log shows the requirement `acquire==3.22`, and the resolving phase completes (cargo compile continuing/killed by timeout is fine). Then `rm -rf build/`.
2. **YAML** — `python3 -c "import yaml; yaml.safe_load(open(f))"` for both `binaries.yml` and `.github/dependabot.yml`; grep-verify: 4 updated install commands, `permissions:`, `concurrency:`, `workflow_dispatch` present, release job `contents: write` intact, action bumps still in place.
3. **CI** — push and confirm: all four jobs green; each "Install dependencies" step installs `dissect.target 3.25.1` (not 3.23.1); pyoxidizer pip logs show `acquire==3.22`.
4. Release machinery is untouched — no re-test needed beyond a normal green run.

## Risks

- Strict `VARS["version"]`: manual builds without `--var version` now fail with a Starlark KeyError — intentional fail-loud; documented in README.
- Plugin-list alignment assumes host install and the bzl's pip download resolve the same `dissect.target` minutes apart in the same job; a release published mid-run could skew one version — failure mode is a stale plugin-list entry (non-fatal).
- `cancel-in-progress` kills in-flight runs on the same ref; re-pushing a tag mid-release cancels the release job mid-upload — recover by deleting the draft and tag, then re-tagging.
- `[full]` host install keeps generating plugin entries for plugins whose deps aren't packaged (e.g. dissect.btrfs) — pre-existing behavior, deferred.

## Out of scope (deferred)

Build-provenance attestations; SHA-pinning actions; `dissect.util==3.24` pin (self-resolves when 3.25 final ships); phantom-plugin cleanup (mirror `pip_args` for the host install); musl forked-pyoxidizer modernization.

## Conventions

- Do not commit — the user handles commits in this repo.
