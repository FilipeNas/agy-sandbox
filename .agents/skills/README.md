# Skills

Agent skills for working on this repo, located directly under `.agents/skills/`.
Each skill is in its own directory with a `SKILL.md` specifying `name` and
`description` frontmatter.

| Skill | Use it for |
| --- | --- |
| [`edit-kit`](edit-kit/SKILL.md) | Changing `agy-sandbox.yaml` (capabilities, policy, hooks, version) or starting a new kit. |
| [`add-tool`](add-tool/SKILL.md) | Baking a new CLI into the image and keeping `context.md` in sync. |
| [`test-kit-locally`](test-kit-locally/SKILL.md) | Building and running the kit from local sources before pushing. |
| [`release`](release/SKILL.md) | Publishing `:latest`/`:nightly`, cutting a dated release, `sbx kit` / cosign signing and verification. |

`edit-kit` is a short, repo-specific cut of upstream
[`create-kit-v3`](https://github.com/docker/sandbox-kit-spec/blob/main/skills/create-kit-v3/SKILL.md);
go there for the full reference.
