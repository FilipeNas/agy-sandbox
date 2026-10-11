---
name: test-kit-locally
description: >-
  Builds the agy-sandbox kit from local sources and runs it with sbx to verify
  changes before pushing. Use after editing agy-sandbox.yaml,
  agy-sandbox.dockerfile, context.md or files/, or when a build fails and logs
  are needed.
---

## Build only (fast check)

From the repo root:

```bash
docker buildx build -f agy-sandbox.yaml -t agy-sandbox:dev .
```

The descriptor is the build file (`# syntax=docker/sandbox-kit:3`); it pulls
in `agy-sandbox.dockerfile` as the content recipe. A YAML or capability error
fails here, before any image layers are built. To validate without exporting,
or to see the resolved declarations without a sandbox:

```bash
docker buildx build . -f agy-sandbox.yaml --output type=cacheonly
sbx kit inspect .
```

## Run it

`sbx` builds a local kit directory automatically. From a throwaway project dir:

```bash
sbx run /home/filipe-nascimento/Personal/agy-sandbox --name agy-dev .
```

Then poke at it:

```bash
sbx exec -it agy-dev bash -l                         # shell
sbx exec agy-dev -- bash -lc 'command -v <tool>'      # tool on PATH (non-interactive)
sbx exec agy-dev -- cat ~/.gemini/antigravity-cli/settings.json   # lifecycle hook ran
sbx exec agy-dev -- cat ~/AGENTS.md                   # context.md got staged
```

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
- [ ] sandbox starts and `agy` launches
- [ ] any new tool resolves in a **non-interactive** shell
- [ ] `context.md` reflects what is actually installed

