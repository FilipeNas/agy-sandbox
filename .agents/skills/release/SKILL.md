---
name: release
description: >-
  Publishes agy-sandbox to GHCR and signs it — how :latest / :nightly get
  built, how to cut a dated release, and how native sbx signing and verification
  work. Use when asked to release, publish, tag, ship, sign or verify a
  version of the kit.
---

All publishing builds go through `.github/workflows/_build-push.yml` (multi-arch, push by
digest, then a manifest list, then sign). It publishes one workload kit image:
`ghcr.io/filipenas/agy-sandbox`. The YAML frontend embeds the descriptor in
that image; no separate kit repository is needed.

## Automatic

`build-and-push.yml`:

| Trigger | Tags |
| --- | --- |
| push to `main` / manual dispatch on `main` | `latest` |
| nightly 03:00 UTC | `nightly`, `latest` |

So merging to `main` is enough to update `:latest`.

Publishing builds smoke-test and scan each native digest before merging tags.
CI-only Trivy scans produce vulnerability reports and SBOMs; findings are
report-only, scanner failures block publication. `scan.yml` rescans `latest`
daily at 07:00 UTC or manually. In `_build-push.yml`, native builds and microVM E2E tests run in parallel, gating tag publication and signing (see `.github/workflows/README.md` for diagrams).

## Dated release

`release.yml` is manual and **main only**. It tags `<YYYY-MM-DD>.<n>` (counter
per day), pushes that tag plus `latest`, then creates the git tag and GitHub
Release. A workflow-level concurrency group serializes version allocation,
publication, and release creation. The reusable workflow also serializes its
merge/sign job across callers.

```bash
gh workflow run release.yml --ref main
gh run watch
```

## Signing

The `merge` job uses native `sbx kit sign` with keyless Sigstore (Fulcio +
Rekor), using ambient GitHub Actions OIDC without long-lived signing keys:

- Takes the **index digest** from `imagetools create --metadata-file`, never
  from a mutable tag lookup.
- Signs and verifies both Linux platform manifests and then the index.
  `sbx kit sign` has no recursive flag, so CI enumerates the platform digests
  explicitly, excluding build-attestation manifests.
- Certificate identity is the reusable workflow at the caller's ref:
  `https://github.com/FilipeNas/agy-sandbox/.github/workflows/_build-push.yml@refs/heads/main`
- The job runs `sbx kit verify` right after each signature; a failure there
  fails the run.

### Verify with `sbx`

Verify a published tag with `sbx`:

```bash
sbx kit verify ghcr.io/filipenas/agy-sandbox:latest \
  --certificate-identity 'https://github.com/FilipeNas/agy-sandbox/.github/workflows/_build-push.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

### Gotchas

- **Every caller of `_build-push.yml` must grant `id-token: write`.** A reusable
  workflow cannot exceed its caller's permissions; without it signing fails
  with an OIDC token error. Keep it scoped to the `merge` job inside
  `_build-push.yml`.
- **The identity names `_build-push.yml`, not the caller** (`release.yml` /
  `build-and-push.yml`), because Fulcio uses the job's workflow ref. Renaming
  or moving `_build-push.yml`, renaming the repo, or building from another branch
  changes the identity — update the README and this skill.
- **Never loosen verification to an owner-wide regexp** — it would accept a
  signature from any workflow in the account.
- When updating `sbx`, update the release version and archive checksum together.
- Do not substitute a successful Cosign check for the native `sbx` check:
  verifier discovery/format compatibility must be tested with the consumer.

## Before releasing

1. Run the `test-kit-locally` skill.
2. Bump `version:` in `agy-sandbox.yaml` if the kit's behaviour changed
   (the release tag is date-based; `version:` is the kit's own semver).
3. Confirm the intended changes are on `main`. Push or dispatch publication
  only with explicit user authorization.
