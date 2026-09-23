# Plan: Publish binaries as draft GitHub Releases from the Action

## Context

- `.github/workflows/binaries.yml` has 4 build jobs (`build-linux-gnu`, `build-linux-musl`, `build-windows`, `build-macos`), each uploading one `actions/upload-artifact@v4` artifact: `acquire-linux`, `acquire-linux-musl` (file `acquire`), `acquire-windows` (file `acquire.exe`), `acquire-macos` (file `acquire`, universal2).
- Trigger is plain `on: push` — this already fires on both branch and tag pushes; leave it untouched.
- Workflow env `VERSION: 3.22`. Existing tags `3.19`/`3.20` (bare numeric, no `v` prefix). No GitHub Releases exist yet.
- Default `GITHUB_TOKEN` has `Contents: write` (verified in recent run logs) — no new secrets needed.
- IMPORTANT: the working tree contains an **uncommitted fix** to this same file (macOS SDK step with dynamic `xcode-select -p` path). Implement on top of it; do not revert or reformat it.

## Decisions (confirmed with user)

1. **Trigger**: pushing a bare version tag equal to `VERSION` (e.g. `3.22`) creates the release. Branch pushes keep today's build-only behavior.
2. **Style**: release is created as a **draft** for manual review before publishing.
3. Include auto-generated release notes, platform-suffixed asset names, and a `SHA256SUMS` file.

## Implementation

Add a `release` job after `build-macos` in `.github/workflows/binaries.yml`:

```yaml
  release:
    name: Draft GitHub Release
    needs: [build-linux-gnu, build-linux-musl, build-windows, build-macos]
    if: startsWith(github.ref, 'refs/tags/')
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Verify tag matches VERSION
        run: |
          if [ "$GITHUB_REF_NAME" != "$VERSION" ]; then
            echo "::error::Tag $GITHUB_REF_NAME does not match workflow VERSION $VERSION — bump VERSION or use a matching tag."
            exit 1
          fi

      - name: Download artifacts
        uses: actions/download-artifact@v4
        with:
          path: dist

      - name: Prepare release assets
        run: |
          mkdir release
          mv dist/acquire-linux/acquire      "release/acquire-${VERSION}-linux-x86_64-gnu"
          mv dist/acquire-linux-musl/acquire "release/acquire-${VERSION}-linux-x86_64-musl"
          mv dist/acquire-windows/acquire.exe "release/acquire-${VERSION}-windows-x86_64.exe"
          mv dist/acquire-macos/acquire      "release/acquire-${VERSION}-macos-universal2"
          cd release && sha256sum * > SHA256SUMS
          ls -l

      - name: Create draft release
        uses: softprops/action-gh-release@v2
        with:
          draft: true
          generate_release_notes: true
          files: release/*
```

### Design notes for the implementer

- **Job-level `if:` cannot use the `env` context** (GitHub Actions restriction: only `github`, `needs`, `vars`, `inputs`). That is why the tag==VERSION check is a first step, not part of the `if:`. The step fails loudly on mismatch instead of silently skipping.
- The rename step is **required**, not cosmetic: the gnu, musl, and macOS binaries are all named `acquire` and would collide as release assets.
- `actions/download-artifact@v4` with only `path:` downloads all artifacts of the run, each into `dist/<artifact-name>/`.
- `softprops/action-gh-release@v2` targets the pushed tag (`GITHUB_REF_NAME`) automatically; on a re-run it updates the existing draft and overwrites assets instead of failing.
- Keep the existing workflow style: actions referenced by major version tag (`@v4`, `@v2`), 2-space indent.
- `permissions: contents: write` is scoped to the release job only (least privilege); build jobs keep default.

## Validation

1. Syntax: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/binaries.yml'))"` (optionally `actionlint` if available).
2. Behavior on a normal branch push: release job appears in the run as *skipped*; all 4 build jobs unchanged.
3. Guard: pushing any tag that does not match `VERSION` → release job fails with the explicit mismatch error, no release created.
4. Real release (when ready to ship): commit any pending fixes, then bump `VERSION` if needed, push, and run:
   ```
   git tag 3.22 && git push origin 3.22
   ```
   Then verify on GitHub: Actions run for tag `3.22` is green; Releases page shows a **draft** `3.22` with 5 assets (4 renamed binaries + `SHA256SUMS`); download one binary and run `--help`; verify checksums (`cd` download dir, `sha256sum -c SHA256SUMS`).

## Risks / edge cases

- Tag pushed before `VERSION` is bumped → guard step fails visibly; fix is to bump `VERSION` and re-tag.
- Re-pushed (forced) tag → existing draft is updated in place by softprops; assets are overwritten.
- Any failing platform build blocks the release entirely (`needs:` all four) — intended.
- Future new build jobs must be added to the `needs:` list and given a rename line, or they silently won't ship.
