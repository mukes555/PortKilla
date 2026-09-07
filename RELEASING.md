# Releasing PortNanny

Releases are automated: pushing a `v*` tag builds a universal DMG + zip and
publishes a GitHub Release whose notes come straight from `CHANGELOG.md`.

## The "What's new" standard

Every release's notes are the **matching `CHANGELOG.md` section**, so there is
one source of truth. `.github/workflows/release.yml` runs
`PortNanny/scripts/release-notes.sh <version>`, which:

1. Extracts the `## <version>` section from `CHANGELOG.md`.
2. Wraps it in a standard **"⚡ What's new in vX.Y.Z"** header + an **Install**
   block (download link, universal/macOS-13 note, quarantine tip).
3. GitHub appends its auto-generated "Full Changelog" compare link below.

Keep changelog entries **user-facing and concise**, grouped under **Added /
Changed / Fixed / Security / Distribution**. Accumulate them under
`## [Unreleased]` as PRs land.

## Cutting a release

1. Move the `[Unreleased]` notes into a new `## <version> (<YYYY-MM-DD>)` section.
2. Bump `VERSION=` in `PortNanny/scripts/build.sh` and the DMG reference in
   `README.md`.
3. Merge to `main` (via PR, never push to `main` directly).
4. Tag and push:
   ```bash
   git tag v<version> && git push origin v<version>
   ```
5. The release workflow does the rest: it refuses to run unless the tag,
   `build.sh`, and the newest CHANGELOG section agree (`scripts/check-version.sh`,
   also run by CI on every PR), verifies the binary is universal and signed
   and that Info.plist carries the tag's version, publishes `SHA256SUMS`, and
   marks `-rc` / `-beta` / `-alpha` tags as pre-releases so `latest` (and the
   Homebrew cask) skip them.

## Homebrew tap updates

With a `HOMEBREW_TAP_TOKEN` repository secret (a fine-grained personal access
token with *Contents: read and write* on `mukes555/homebrew-tap`), the release
workflow renders `packaging/homebrew/portnanny.rb.tmpl` with the version and
the zip's SHA-256 and pushes it to the tap, so `brew upgrade --cask portnanny`
sees new releases and Homebrew verifies the download. Without the secret the
job skips and the tap keeps its `version :latest` cask, which needs
`brew reinstall` to update. Add the secret under Settings → Secrets and
variables → Actions in the PortNanny repository.

## Preview release notes locally

```bash
bash PortNanny/scripts/release-notes.sh 1.6.0
```

## Versioning

Semantic-ish: **minor** bump for new features (1.5 → 1.6), **patch** for
fixes-only (1.6.0 → 1.6.1). The version lives in `scripts/build.sh` and is
surfaced in the app's Info.plist and the `portnanny version` CLI command.
