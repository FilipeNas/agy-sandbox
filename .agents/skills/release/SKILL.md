---
name: release
description: >-
  Publishes agy-sandbox to GHCR and signs it — how :latest / :nightly get
  built, how to cut a dated release, and how cosign signing and verification
  work. Use when asked to release, publish, tag, ship, sign or verify a
  version of the kit.
---

All builds go through `.github/workflows/_build.yml` (multi-arch, push by
digest, then a manifest list, then sign). It pushes two names with the same
tags and the same digest:

- `ghcr.io/filipenas/agy-sandbox` — the image
- `ghcr.io/filipenas/agy-sandbox-kit` — the kit

## Automatic

`build-and-push.yml`:

| Trigger | Tags |
|---|---|
| push to `main` / manual dispatch | `latest` |
| nightly 03:00 UTC | `nightly`, `latest` |

So merging to `main` is enough to update `:latest`.

## Dated release

`release.yml` is manual and **main only**. It tags `<YYYY-MM-DD>.<n>` (counter
per day), pushes that tag plus `latest`, then creates the git tag and GitHub
Release.

```bash
gh workflow run release.yml --ref main
gh run watch
```

## Signing

The `merge` job signs keyless using Sigstore (compatible with `sbx kit` and `cosign`) — no keys or secrets:

- Signs the **index digest**, never a tag, with `--recursive` (each platform
  manifest too), for **both** repositories (`agy-sandbox` and `agy-sandbox-kit`).
- Certificate identity is the reusable workflow at the caller's ref:
  `https://github.com/FilipeNas/agy-sandbox/.github/workflows/_build.yml@refs/heads/main`
- The job verifies its own signature right after signing; a failure there
  fails the run.

### Verify with `sbx` or `cosign`

Verify a published tag with `sbx`:

```bash
sbx kit verify ghcr.io/filipenas/agy-sandbox:latest \
  --certificate-identity 'https://github.com/FilipeNas/agy-sandbox/.github/workflows/_build.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Or with `cosign`:

```bash
cosign verify ghcr.io/filipenas/agy-sandbox:latest \
  --certificate-identity 'https://github.com/FilipeNas/agy-sandbox/.github/workflows/_build.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

### Gotchas

- **Every caller of `_build.yml` must grant `id-token: write`.** A reusable
  workflow cannot exceed its caller's permissions; without it signing fails
  with an OIDC token error. Keep it scoped to the `merge` job inside
  `_build.yml`.
- **The identity names `_build.yml`, not the caller** (`release.yml` /
  `build-and-push.yml`), because Fulcio uses the job's workflow ref. Renaming
  or moving `_build.yml`, renaming the repo, or building from another branch
  changes the identity — update the README and this skill.
- **Never loosen verification to an owner-wide regexp** — it would accept a
  signature from any workflow in the account.
- Pin `sigstore/cosign-installer` by commit SHA like the other actions.

## Before releasing

1. Run the `test-kit-locally` skill.
2. Bump `version:` in `agy-sandbox.yaml` if the kit's behaviour changed
   (the release tag is date-based; `version:` is the kit's own semver).
3. Make sure everything is pushed to `main`.
