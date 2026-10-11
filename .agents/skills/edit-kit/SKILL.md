---
name: edit-kit
description: >-
  Changes the agy-sandbox kit descriptor (agy-sandbox.yaml) — capabilities,
  network policy, credentials, lifecycle hooks, agent context, provides and
  version — or starts a new kit alongside it. Use when adding or changing a
  capability, bumping the kit version, or asking what a descriptor field does.
---

This repo is one **workload** kit in the default companion-pair layout:

| File | Role |
|---|---|
| `agy-sandbox.yaml` | descriptor; first line `# syntax=docker/sandbox-kit:3` |
| `agy-sandbox.dockerfile` | content recipe, found by filename stem |
| `context.md` | agent-context body (`contentFile:`), staged as `AGENTS.md` |
| `files/home/` | dotfiles copied into `/home/agent` |

For anything not covered here, read upstream
[`create-kit-v3`](https://github.com/docker/sandbox-kit-spec/blob/main/skills/create-kit-v3/SKILL.md)
and the [capability pages](https://github.com/docker/sandbox-kit-spec/tree/main/docs/spec/capabilities/com.docker.sandbox).

## Rules that bite

- **Strict decoding.** Unknown or misspelled keys are errors. Keys are
  `lowerCamelCase` (`sourceUrl`, `contentFile`).
- **Capabilities are required by default.** Add `optional: true` if the kit
  still works without it (as with the Google OAuth `credential@1`).
- **`network-policy` is phase-scoped.** An absent phase grants nothing: hosts
  reached by `install` hooks go under `install`, hosts reached by the agent go
  under `runtime`. `@1` (by host) and `@2` (host + method + path) are
  mutually exclusive — never declare both.
- **Credential hosts must be allowed.** Every OAuth/inject host must appear in
  the allow list of the same phase (currently satisfied by `'*'`; matters if
  the policy is ever tightened).
- **Lifecycle hook env is deny-by-default.** List every variable a hook (or a
  child process) reads in `env:` — e.g. `WORKSPACE_DIR`, `HTTP_PROXY`,
  `HTTPS_PROXY`.
- **`sbx@1` is workload-only.** It is what makes `sbx` launch this as an agent.
- **Unversioned `provides` fall back to `version:`.** `agy` under
  `version: 0.1.0` publishes `agy@0.1.0` — the kit's number, not agy's. Fine
  for personal use; pin via a build arg if anything ever `requires` it.
- **Prefer `ENV` in the dockerfile** over profile/rc files for anything the
  agent needs; the agent runs non-interactive bash via `BASH_ENV`.

## Workflow

1. Edit `agy-sandbox.yaml` (and `context.md` if the agent should know).
2. Validate fast — the descriptor is checked before any layer builds:
   ```bash
   docker buildx build . -f agy-sandbox.yaml --output type=cacheonly
   sbx kit inspect .        # resolved declarations, no sandbox
   ```
   (`sbx kit validate` does **not** accept v3 source kits.)
3. Run it with the `test-kit-locally` skill. Inside the sandbox:
   - `/usr/share/sandbox/kit/<kit>/kit.yaml` — the published descriptor
   - `/var/log/sbx-kit-startup.log` — hook output
4. Bump `version:` if behaviour changed, then follow the `release` skill.

## Starting a new kit

Most new kits should be a **mixin** (adds a tool/credential/policy to someone
else's workload) rather than another workload. Put it in its own directory with
the same stem layout (`<kit>/<kit>.yaml`, `<kit>/<kit>.dockerfile`,
`<kit>/<kit>-context.md`) — the descriptor's directory is the build context.
A mixin cannot set `ENTRYPOINT`/`CMD`/`USER`/`WORKDIR` and cannot declare
`sbx@1`. Run it composed:

```bash
sbx run . --kit ./<kit> <project-dir>
```

Copy from upstream examples: `gh` (tool mixin), `hello` (smallest workload),
`claude` / `claude-mixin` (one agent in both shapes).

