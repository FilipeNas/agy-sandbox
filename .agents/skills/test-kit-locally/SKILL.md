---
name: test-kit-locally
description: >-
  Builds the agy-sandbox kit from local sources and runs it with sbx to verify
  changes before pushing. Use after editing agy-sandbox.yaml,
  agy-sandbox.dockerfile, context.md or files/, or when a build fails and logs
  are needed.
---

## Build only

From the repo root:

```bash
docker buildx build -f agy-sandbox.yaml -t agy-sandbox:dev --load .
```

The descriptor is the build file (`# syntax=docker/sandbox-kit:3`); it pulls
in `agy-sandbox.dockerfile` as the content recipe. A YAML or capability error
fails here, before any image layers are built. To validate without exporting,
or to see the resolved declarations without a sandbox:

```bash
docker buildx build . -f agy-sandbox.yaml --output type=cacheonly
sbx kit inspect .
```

`cacheonly` skips export, not image-layer execution; uncached builds can take time.

## Image smoke tests

Load the current kit into Docker and run the same offline suite as CI:

```bash
docker buildx build . -f agy-sandbox.yaml -t agy-sandbox:dev --load
bash tests/image.sh agy-sandbox:dev
```

The suite checks tool paths and execution, shell initialization, launch
configuration, agent permissions, Git LFS round-trips, bundled files, and
workspace-trust hook idempotence and settings permissions. Pull requests
run it on both native architectures without publishing. Publishing builds
also check the registry's OCI kit descriptor before exporting their digest
to the merge job.

For mounted/mountless microVM, context, workspace-trust, nested Docker and
network checks, run `bash tests/e2e.sh`. Credential proxying remains untested.
CI E2E is manual, main-only and hosted amd64; configure repository variable
`DOCKER_USERNAME` and secret `DOCKER_PAT`. It is not a publication gate.
The full suite remains unverified after a local injected-context failure.

## Run it

`sbx` builds a local kit directory automatically. From a throwaway project dir:

```bash
sbx run /path/to/agy-sandbox --name agy-dev .
```

Then poke at it:

```bash
sbx exec -it agy-dev bash -l                         # shell
sbx exec agy-dev -- bash -lc 'command -v <tool>'      # tool on PATH (non-interactive)
sbx exec agy-dev -- bash -lc 'cat "$HOME/.gemini/antigravity-cli/settings.json"'
```

Injected `AGENTS.md` may be in home, the workspace, or its parent; the E2E
script checks those locations and compares the staged context.

Clean up when done:

```bash
sbx rm agy-dev
```

## When a build fails

```bash
docker buildx history ls
docker buildx history logs <build-id>
```

## Checklist

- [ ] `docker buildx build` succeeds
- [ ] `bash tests/image.sh agy-sandbox:dev` passes
- [ ] sandbox starts and `agy` launches
- [ ] any new tool resolves in a **non-interactive** shell
- [ ] `context.md` reflects what is actually installed

