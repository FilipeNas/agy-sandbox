# agy-sandbox

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) Kit (v3) packaging Google's **Antigravity CLI (`agy`)** inside a hardware-virtualized microVM.

Pre-bakes a comprehensive DevOps environment (Kubernetes, OpenTofu, AWS CLI, `pgcli`, `uv`, shell utilities) directly into the image for sub-second startup times without runtime installation latency.

> [!NOTE]
> Inspired by Oleg Šelajev's [agy-sbx-kit](https://github.com/shelajev/agy-sbx-kit).

---

## Installation & Setup

### 1. Install Docker Sandboxes CLI (`sbx`)

Follow the official [Docker Sandboxes Installation Guide](https://docs.docker.com/ai/sandboxes/install/) for platform-specific packages.

### 2. Authenticate CLI

```bash
sbx login
```

### 3. Registry Authentication & Permissions (GHCR)

Configure Docker and `sbx` to pull kits from the GitHub Container Registry:

```bash
# Authenticate GitHub CLI with package read access
gh auth login --scopes "read:packages"

# Configure registry credentials for Docker and sbx
gh auth token | docker login ghcr.io -u <your-github-username> --password-stdin
gh auth token | sbx secret set --registry ghcr.io --username <your-github-username> --password-stdin

# Allow kits from GHCR and initialize network policy
sbx settings set kit.allowedSources '["docker.io/","ghcr.io/filipenas/"]'
sbx policy init allow-all
```

### 4. Optional Host Configuration

```bash
# Enable experimental platform features and UDP egress
sbx settings set platform.allowExperimentalFeatures true
sbx settings set feature.udp-egress true

# Allocate persistent volume disk size (e.g. 20GB)
sbx settings set sandbox.disk.dockerVolume 20g
sbx daemon restart

# Configure SSH host entries for terminal and IDE Remote-SSH access (ssh <name>.sbx)
sbx setup ssh
```

---

## Running Sandboxes

### Launching the Agent

Mount a host project directory into the sandbox as the primary writable workspace:

```bash
sbx run ghcr.io/filipenas/agy-sandbox:latest --name agy-sandbox ~/Personal/my-project
```

Running `sbx run` without a trailing path automatically defaults to mounting the current working directory (`.`).

---

### Workspace Mounting Modes

Docker Sandboxes provisions the primary workspace using one of three execution modes ([reference](https://docs.docker.com/ai/sandboxes/usage/#git-workspace-modes)):

#### Direct Mode (Default)

Binds the host filesystem path directly into the microVM with read-write access. Host path topology is mirrored (`/home/<user>/...`), and all edits reflect on the host immediately:

```bash
sbx run ghcr.io/filipenas/agy-sandbox:latest --name agy-sandbox ~/Personal/my-project
```

#### Clone Mode (`--clone`)

Clones the target Git repository into an isolated in-container filesystem. The host repository is mounted read-only at `/run/sandbox/source`. In-container commits must be fetched or pushed before the sandbox is removed:

```bash
# Clone local Git repository
sbx run --clone ghcr.io/filipenas/agy-sandbox:latest --name agy-sandbox .

# Clone remote Git repository directly
sbx run --clone ghcr.io/filipenas/agy-sandbox:latest --name agy-sandbox https://github.com/owner/repo.git
```

#### Mountless Mode

Omitting workspace paths creates a sandbox operating entirely within the container's isolated root filesystem at `WORKDIR` (`/home/agent/workspace`). No host directories are exposed:

```bash
sbx run ghcr.io/filipenas/agy-sandbox:latest --name agy-sandbox
```

#### Multiple Workspaces

Additional directories can be attached alongside the primary workspace. The first argument designates the primary workspace; secondary paths support the `:ro` read-only modifier ([reference](https://docs.docker.com/ai/sandboxes/usage/#multiple-workspaces)):

```bash
sbx run ghcr.io/filipenas/agy-sandbox:latest ~/project-a ~/shared-libs ~/docs:ro
```

---

## Authentication

Antigravity uses headless Google OAuth mediated by the Docker Sandboxes credential proxy:

1. On initial startup, `agy` detects missing host credentials and displays an unauthenticated eligibility prompt. Press Enter to trigger the `/logout` command.
2. Select **`1. Google OAuth`**.
3. Open the displayed URL in your host browser, sign in, and grant permissions.
4. Copy the authorization code (`4/...`) from the browser, paste it into the terminal prompt, and press Enter.
5. The `sbx` daemon captures and stores the OAuth token in the **host credential store**.

Subsequent sandboxes automatically boot authenticated. The container filesystem holds proxy sentinel tokens (`agy-oauth-access-proxy-managed`), which the host daemon dynamically swaps for active tokens during outbound requests to Google AI APIs.

---

## Sandbox Lifecycle Management

```bash
# List active and stopped sandboxes
sbx ls

# Execute commands or open a login shell in an active sandbox
sbx exec -it agy-sandbox bash -l
sbx exec agy-sandbox -- agy --help

# Copy files between host and sandbox
sbx cp ~/local-file agy-sandbox:/home/agent/workspace/
sbx cp agy-sandbox:/home/agent/workspace/artifact.tar.gz ./

# Suspend and destroy sandboxes
sbx stop agy-sandbox
sbx rm agy-sandbox
```

---

## Local Development

### Testing Local Changes

To test local modifications in a sandbox without publishing to a remote registry:

```bash
# Test run against a target project directory
sbx run /path/to/agy-sandbox --name agy-dev .

# Or build locally to validate syntax and compilation
docker buildx build -f agy-sandbox.yaml -t agy-sandbox:dev .
```

`sbx` resolves the local kit files (`agy-sandbox.yaml`, `agy-sandbox.dockerfile`) and triggers an automatic local BuildKit compilation.

### Inspecting BuildKit Logs

BuildKit logs from local runs are recorded in Docker build history:

```bash
# List recent build invocations
docker buildx history ls

# Tail detailed build logs by Build ID
docker buildx history logs <build-id>
```

---

## Signing & Verification

Every image and kit published by CI is signed using **keyless** Sigstore signatures (Fulcio + Rekor), which are directly supported by `sbx kit` and interoperable with `cosign`:

1. The `merge` job in `_build.yml` receives a short-lived GitHub OIDC token (`id-token: write`).
2. Sigstore's Fulcio issues an ephemeral signing certificate bound to the workflow identity: `https://github.com/FilipeNas/agy-sandbox/.github/workflows/_build.yml@refs/heads/main`.
3. The signature is attached as an OCI referrer to the index manifest in GHCR and logged in Rekor.

Both `agy-sandbox` and `agy-sandbox-kit` are signed. Signing changes neither the image digest nor the kit annotations.

### Verify Signature

Verify the published kit against the signing identity using `sbx`:

```bash
sbx kit verify ghcr.io/filipenas/agy-sandbox:latest \
  --certificate-identity 'https://github.com/FilipeNas/agy-sandbox/.github/workflows/_build.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

*(You can also use `cosign verify` with the identical flags).*

To require valid signatures automatically when running kits:

```bash
sbx settings set kit.trustedSigners '[{"identity":"https://github.com/FilipeNas/agy-sandbox/.github/workflows/_build.yml@refs/heads/main","issuer":"https://token.actions.githubusercontent.com"}]'
sbx settings set kit.requireSignature true
```

---

## Architecture & Specifications

- **Kit v3 OCI Descriptor**: Conforms to the [Docker Sandbox Kit Specification v3](https://github.com/docker/sandbox-kit-spec) (`# syntax=docker/sandbox-kit:3`). Capabilities, network egress policies, and credential proxies are declared in `agy-sandbox.yaml` and embedded into the OCI manifest annotations.
- **Dynamic Workspace Trust**: On startup, a `com.docker.sandbox/lifecycle@1` install hook automatically queries `$WORKSPACE_DIR` and injects it into `~/.gemini/antigravity-cli/settings.json`, bypassing Antigravity directory trust prompts.
- **Context Injection**: `context.md` is registered via `com.docker.sandbox/agent-context@1` and staged as `AGENTS.md` to instruct the agent on container conventions, pre-baked tooling, and execution semantics.

---

## References

- [Docker Sandbox Kit Specification](https://github.com/docker/sandbox-kit-spec)
- [Docker Sandboxes Documentation](https://docs.docker.com/ai/sandboxes/)
- [Docker Sandboxes Installation Guide](https://docs.docker.com/ai/sandboxes/install/)
- [Docker Sandboxes Git Workspace Modes](https://docs.docker.com/ai/sandboxes/usage/#git-workspace-modes)
- [Docker Sandboxes Multiple Workspaces](https://docs.docker.com/ai/sandboxes/usage/#multiple-workspaces)
- [Google Antigravity CLI Getting Started](https://antigravity.google/docs/getting-started)
- [Oleg Šelajev's agy-sbx-kit](https://github.com/shelajev/agy-sbx-kit)
