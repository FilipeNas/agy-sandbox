# agy-sandbox

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) **workload kit (v3)** packaging Google's **Antigravity CLI (`agy`)** inside a hardware-virtualized microVM.

Includes Kubernetes, OpenTofu, AWS CLI, `pgcli`, `uv`, and shell utilities; no runtime tool installation required.

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

Create a new sandbox with `sbx create` and omit workspace paths, then attach by name. The sandbox operates at `WORKDIR` (`/home/agent/workspace`) without a host workspace bind mount:

```bash
sbx create ghcr.io/filipenas/agy-sandbox:latest --name filipe-sbx
sbx run --name filipe-sbx
```

Omitting the path from `sbx run` when creating a sandbox instead mounts the current directory read-write. Use a new name for a mountless sandbox; attaching to an existing sandbox does not change its mounts.

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
docker buildx build -f agy-sandbox.yaml -t agy-sandbox:dev --load .
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

## Tests

### Workflow Map

| Workflow | Trigger | Role |
| --- | --- | --- |
| [test.yml](.github/workflows/test.yml) | Pull request or manual | Lint scripts, build and smoke-test both native architectures; no publication |
| [build-and-push.yml](.github/workflows/build-and-push.yml) | Push to `main`, nightly 03:00 UTC, or manual on `main` | Call the shared publisher for `latest` or `nightly,latest` |
| [_build-push.yml](.github/workflows/_build-push.yml) | Reusable workflow call | Build, smoke-test, scan both architectures and run microVM E2E in parallel; merge, sign and verify |
| [release.yml](.github/workflows/release.yml) | Manual on `main` | Allocate a dated version, await the shared publisher, then create the GitHub release |
| [scan.yml](.github/workflows/scan.yml) | Daily 07:00 UTC or manual | Resolve `latest` once; rescan both platforms without publishing |

### Image Tests

Pull requests build and test on native amd64 and arm64 runners without publishing. Publishing builds run the same tests against their pushed digest before updating tags, plus checks for the embedded OCI kit descriptor.

```bash
docker buildx build . -f agy-sandbox.yaml -t agy-sandbox:dev --load
bash tests/image.sh agy-sandbox:dev
```

The offline smoke suite checks installed tools, CLI execution, shell setup, agent identity, launch configuration, Git LFS round-trips, bundled settings/context, and workspace-trust hook behavior (including idempotence and file permissions).

Container tests do not cover microVM startup, nested Docker, or network enforcement; use the E2E suite for those. Google OAuth remains untested. Native signing verification runs during publication.

### End-to-End

```bash
bash tests/e2e.sh
```

The suite builds the local kit and checks mounted/mountless workspaces, context injection, trust, host writes, nested Docker, and network policy. Commands are timeout-bounded; cleanup removes only its test sandboxes.

For the manual **end-to-end** workflow on `main`, configure repository Actions credentials:

- Variable `DOCKER_USERNAME`: your Docker ID.
- Secret `DOCKER_PAT`: Docker PAT with at least Read scope.

In CI, E2E runs on hosted amd64 with KVM and a checksum-pinned full sbx runtime (arm64 is covered by image tests). Tests run concurrently with multi-arch builds in `_build-push.yml` on merges to `main`, nightly runs, and releases, strictly gating publication: kits are only pushed and signed if all image and microVM tests pass. Login uses headless Docker authentication (`DOCKER_USERNAME` / `DOCKER_PAT`) with automatic logout. For CI/CD architecture diagrams and execution flows, see [.github/workflows/README.md](.github/workflows/README.md).

### Dependency Scanning

CI scans both platforms by immutable digest using SHA-pinned `aquasecurity/trivy-action` and an explicit CLI version. Scans run before publication and daily at 07:00 UTC or manually against resolved `latest`, filtering to fixable `CRITICAL` and `HIGH` OS package vulnerabilities (`vuln-type: os`, `ignore-unfixed: true`).

Each platform's `dependency-reports-*` artifact contains:

- `vulnerabilities.json`: findings, affected packages, and available fixes (JSON).
- `vulnerabilities.txt`: human-readable Trivy table report.
- `vulnerabilities.sarif`: SARIF report uploaded to GitHub Security (Code scanning).
- `sbom.cdx.json`: CycloneDX component inventory.
- `image.txt`: the scanned immutable reference.

Each scan also renders a human-readable Markdown summary table directly on the GitHub Actions run page (`$GITHUB_STEP_SUMMARY`) and uploads SARIF results to the repository's **Security → Code scanning** tab. Findings are report-only; scanner/database failures fail the job. Reports are retained for 7 days. Third-party Homebrew and standalone binaries such as `agy` are excluded from OS vulnerability scans (though inventoried in the SBOM); findings do not establish exploitability or safety.

Dependabot updates action SHAs weekly. Renovate groups sbx version/checksum updates and Trivy CLI versions, without duplicating Actions PRs. Neither automerges. Install the [Renovate GitHub App](https://github.com/apps/renovate) to activate it; other container digests still need explicit updates.

---

## Signing & Verification

`ghcr.io/filipenas/agy-sandbox` is the workload kit image. Build via `agy-sandbox.yaml` to include the kit descriptor; no separate artifact is needed.

CI uses native `sbx kit sign` / `verify` with GitHub OIDC and Sigstore (Fulcio + Rekor). It signs and verifies the index and both platform manifests by digest, storing signatures as OCI referrers. The index digest comes from build metadata, not a tag lookup.

### Verify Signature

Verify:

```bash
sbx kit verify ghcr.io/filipenas/agy-sandbox:latest \
  --certificate-identity 'https://github.com/FilipeNas/agy-sandbox/.github/workflows/_build-push.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Require signatures when running kits:

```bash
sbx settings set kit.trustedSigners '[{"identity":"https://github.com/FilipeNas/agy-sandbox/.github/workflows/_build-push.yml@refs/heads/main","issuer":"https://token.actions.githubusercontent.com"}]'
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
