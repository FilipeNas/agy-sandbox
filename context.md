# agy-sandbox Agent Context

## Environment

You are operating inside an isolated Docker Sandbox microVM (Ubuntu 26.04) running as the `agent` user with passwordless `sudo` privileges.

### Workspace Modes

- **Direct Mode**: The workspace is a bind mount of the developer's host directory. Edits and deletions modify the actual files on the host machine in real time.
- **Clone Mode (`--clone`)**: The workspace is an in-container Git clone. Any changes stay inside this clone until fetched or pushed. The original host repository is mounted read-only at `/run/sandbox/source`.
- **Mountless Mode**: If no host path was supplied at creation time, the agent operates entirely within the container's isolated filesystem at `/home/agent/workspace`.

Everything outside mounted workspace paths is VM-local and ephemeral (destroyed when the sandbox is removed).

### Network & Connectivity

- The network policy permits outbound HTTP and HTTPS traffic to all destinations.
- ICMP (`ping`) is blocked at the microVM network layer; test connectivity using `curl`, `nc`, or `websocat`.

---

## Tooling & Path Execution

All developer tools are pre-baked into the image for zero installation latency. The shell environment is configured via `BASH_ENV=/etc/sandbox-persistent.sh`, guaranteeing that all binary paths are exported in both interactive shells and automated subshell tool calls:

- **Version Control & GitHub**: `git`, `git-lfs`, GitHub CLI (`gh`).
- **Kubernetes**: `kubectl` (aliased to `kubecolor` interactively), `kubectx`, `krew` (`~/.krew/bin` in PATH), `kustomize`, `helm`, `stern`.
- **Infrastructure as Code (IaC)**: OpenTofu (`tofu`), Terragrunt (`terragrunt`), `tflint`, `terraform-docs`.
- **Cloud & Databases**: AWS CLI v2 (`aws`), `awscurl`, `awsdac`, `docker-credential-helper-ecr`, `pgcli`, MySQL client (`mysql`).
- **Containers**: Docker Engine & Docker CLI (`docker`, `docker compose`, `docker buildx`) are fully operational inside the microVM.
- **Python Tooling**: `uv` (package manager & runner), `ruff`, `isort`, `pre-commit` (installed via `uv tool`). Run ad-hoc tools with `uv tool run <tool>` or install with `uv tool install <pkg>`.
- **Shell Utilities**: `ripgrep` (`rg`), `jq`, `yq`, `fzf`, `zoxide` (`z`), `nmap`, `ipcalc`, `websocat`, `nano`.
- **Agent Binary**: Google Antigravity CLI (`agy`) located at `/usr/local/bin/agy`.

> [!NOTE]
> Prefer `brew install <tool>` or `uv tool install <pkg>` for user-space utilities. Use `sudo apt-get install <pkg>` for system-level dependencies.

---

## Authentication & Security Model

- **Google OAuth**: Handled transparently by Docker Sandboxes' host credential proxy. `~/.gemini/antigravity-cli/antigravity-oauth-token` holds sentinel tokens that the host proxy replaces with active credentials when contacting Google AI APIs.
- **Agent Autonomy**: The hardware-virtualized microVM provides the isolation boundary, allowing Antigravity to operate in permissive mode (`--dangerously-skip-permissions --mode=accept-edits`).
