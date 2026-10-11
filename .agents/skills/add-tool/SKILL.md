---
name: add-tool
description: >-
  Adds (or removes) a CLI tool baked into the agy-sandbox image — via Homebrew,
  uv tool, or apt — and keeps context.md in sync. Use when asked to install,
  add, bake in, or drop a tool from the sandbox image.
---

Tools are baked at build time in `agy-sandbox.dockerfile`. Pick the stage by
how the tool is distributed:

| Source | Stage | Where |
|---|---|---|
| Homebrew formula (default choice) | `brew` | the `brew install` list |
| Python CLI | `pytools` | the `for t in ...; do uv tool install` loop |
| System lib / needs root | `system` | the `apt-get install` list |

## Steps

1. Add the package name to the right list. Keep the brew list **alphabetical**.
   Tap formulas use the full name (e.g. `terraform-linters/tap/tflint`).
2. If the tool installs outside the default PATH (keg-only brew formula, e.g.
   `mysql-client`), add its `bin` to the `ENV PATH=` block in the `final` stage.
3. If it needs post-install setup as root, add it to the `RUN` in `final`
   (next to `git-lfs install`).
4. Update the matching bullet in `context.md` under **Tooling & Path
   Execution** so the agent inside the sandbox knows it exists.
5. Update the tool list in `README.md` intro only if it is a headline tool.
6. Verify with the `test-kit-locally` skill — at minimum confirm the binary
   resolves inside the sandbox: `sbx exec <name> -- bash -lc 'command -v <tool>'`.

## Gotchas

- Do not install tools in the `final` stage directly; stages `brew`, `pytools`
  and `agy` build in parallel and are copied in.
- The agent runs non-interactive shells; PATH comes from `ENV` and
  `/etc/sandbox-persistent.sh` (via `BASH_ENV`), not `.bashrc`. Aliases in
  `files/home/.bashrc` only affect interactive shells.
- Both `linux/amd64` and `linux/arm64` are built in CI — make sure the
  package exists for both.

