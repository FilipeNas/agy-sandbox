# Working in this repository

Guidance for AI coding agents (and the human steering them) making changes to
**agy-sandbox**: a [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/)
Kit (v3) that packages the Antigravity CLI (`agy`) and a DevOps toolbelt in a
microVM, published to GHCR.

> [!NOTE]
> This file is for working **on** the repo. `context.md` is a different thing:
> it is shipped **into** the sandbox (staged as `AGENTS.md` there) and tells
> the agent running inside about its environment. Don't mix the two.

## What this repository is

| Part | Where | What it is |
|---|---|---|
| Kit descriptor | `agy-sandbox.yaml` | v3 descriptor (`# syntax=docker/sandbox-kit:3`): kind, version, provides, capabilities (network policy, Google OAuth credential, agent context, lifecycle hook) |
| Content recipe | `agy-sandbox.dockerfile` | Multi-stage image: Homebrew tools, `uv` tools, `agy`, dotfiles. Found by filename stem |
| In-sandbox context | `context.md` | What the agent inside the sandbox reads. Must match what the image installs |
| Dotfiles | `files/home/` | Copied to `/home/agent` |
| CI/CD | `.github/workflows/` | `_build.yml` builds, pushes and cosign-signs; `build-and-push.yml` (`:latest`, `:nightly`) and `release.yml` (dated tags) call it |
| Skills | `.agents/skills/` | Agent skills for this repo (see below) |

When the upstream spec and something here disagree, the
[spec](https://github.com/docker/sandbox-kit-spec) wins.

## Before you start

Read the matching skill in `.agents/skills/` and follow it:

| Task | Skill |
|---|---|
| Change `agy-sandbox.yaml` or start a new kit | `.agents/skills/edit-kit/SKILL.md` |
| Add or remove a tool in the image | `.agents/skills/add-tool/SKILL.md` |
| Build / run locally, debug a build | `.agents/skills/test-kit-locally/SKILL.md` |
| Publish, tag, sign or verify | `.agents/skills/release/SKILL.md` |

Toolchain: Docker with buildx, the `sbx` CLI (including `sbx kit sign` / `sbx kit verify`), and `gh`.

## Verifying a change

There is no test suite; verification is building and running the kit.

| Check | Command | When |
|---|---|---|
| Descriptor validates | `docker buildx build . -f agy-sandbox.yaml --output type=cacheonly` | Every change. Fails in seconds on a bad field |
| Resolved declarations | `sbx kit inspect .` | Capability / policy changes |
| Full build | `docker buildx build . -f agy-sandbox.yaml -t agy-sandbox:dev` | Dockerfile changes |
| Runs end to end | `sbx run <path-to-this-repo> --name agy-dev <project>` | Before pushing anything that changes the image |

CI builds `linux/amd64` and `linux/arm64`; anything added must exist for
both.

## Rules

- **Keep `context.md` honest.** If the image gains or loses a tool, a path or a
  policy, update `context.md` in the same change.
- **Never push or release unprompted.** Pushing to `main` publishes `:latest`
  immediately.
- **Don't weaken signing.** Keep `id-token: write` on callers of
  `_build.yml`, sign by digest, and keep verification pinned to the exact
  workflow identity.
- **Pin GitHub Actions by commit SHA** with the version in a trailing comment.

## Branches

`<type>/<short-description>`, lowercase and hyphenated, with a type from the
commit conventions below — e.g. `feat/add-k9s`, `ci/cosign-signing`. No AI
tool or agent names in branch names (`claude/`, `cursor/`, `agy/`, …).

## Commits

[Conventional Commits](https://www.conventionalcommits.org/):

```text
<type>(<scope>): <imperative, lowercase summary, no trailing period>
```

Types: `feat`, `fix`, `docs`, `chore`, `ci`, `refactor`. Scopes: `kit`
(descriptor), `image` (dockerfile / dotfiles), `context`, `ci`, `skills`,
`readme`, `deps`.

```text
feat(image): add k9s
fix(kit): declare HTTPS_PROXY for the install hook
ci: sign image and kit with cosign
docs(skills): add release signing notes
```

The body explains *why* when the diff cannot.

