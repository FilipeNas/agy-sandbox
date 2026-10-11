# syntax=docker/dockerfile:1

# Prebuilt image for the agy-sandbox kit.
# All tools are baked directly into the image so sandboxes start up instantly.
#
# Build architecture:
# - Multi-stage parallel builds: Homebrew CLIs, Python uv tools, and Antigravity CLI (agy)
#   build concurrently for fast build times.
# - Cache mounts (--mount=type=cache) persist download caches across builds.
# - Toolchains: Homebrew manages CLI utilities, including 'uv'. Even though the base image
#   ships with a system uv binary, we install and manage uv via Homebrew for unified updates.
# - Environment: The base image sets ENV BASH_ENV=/etc/sandbox-persistent.sh, and .bashrc
#   also sources it. Adding Homebrew's shellenv here exports PATH across both interactive
#   sessions and non-interactive agent subshells.

ARG BASE=docker/sandbox-templates:shell-docker-nightly

# ── system: shared base ───────────────────────────────────────────────────────
FROM ${BASE} AS system
USER root
# System dependencies:
# - build-essential, procps, curl, file, git: required prerequisites to install Homebrew
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends \
      build-essential procps curl file git

# Evaluated by interactive shells and non-interactive subshells via $BASH_ENV
RUN cat > /etc/sandbox-persistent.sh <<'EOF'
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
EOF

# ── brew: Homebrew + CLI tools ────────────────────────────────────────────────
FROM system AS brew
USER agent
ARG TARGETARCH
ENV NONINTERACTIVE=1 \
    HOMEBREW_NO_AUTO_UPDATE=1 \
    HOMEBREW_NO_ANALYTICS=1 \
    HOMEBREW_NO_ENV_HINTS=1 \
    PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
RUN --mount=type=cache,id=homebrew-${TARGETARCH},target=/home/agent/.cache/Homebrew,uid=1000,gid=1000 \
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
RUN --mount=type=cache,id=homebrew-${TARGETARCH},target=/home/agent/.cache/Homebrew,uid=1000,gid=1000 \
    brew install \
      awscli awscurl awsdac docker-credential-helper-ecr fzf gh git-lfs helm ipcalc jq \
      krew kubecolor kubectx kubernetes-cli kustomize mysql-client nano nmap \
      opentofu pgcli ripgrep stern terraform-docs terragrunt \
      terraform-linters/tap/tflint uv websocat yq zoxide

# ── pytools: uv Python tools ──────────────────────────────────────────────────
FROM system AS pytools
USER agent
ARG TARGETARCH
RUN --mount=type=cache,id=uv-${TARGETARCH},target=/home/agent/.cache/uv,uid=1000,gid=1000 \
    for t in isort ruff pre-commit; do uv tool install "$t"; done

# ── agy: Antigravity CLI ──────────────────────────────────────────────────────
FROM system AS agy
USER agent
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash

# ── final ─────────────────────────────────────────────────────────────────────
FROM system AS final
COPY --from=brew    --chown=agent:agent /home/linuxbrew/.linuxbrew     /home/linuxbrew/.linuxbrew
COPY --from=pytools --chown=agent:agent /home/agent/.local             /home/agent/.local
COPY --from=agy     --chown=agent:agent /home/agent/.local/bin/agy     /home/agent/.local/bin/agy
USER root
RUN ln -sf /home/agent/.local/bin/agy /usr/local/bin/agy \
 && /home/linuxbrew/.linuxbrew/bin/git-lfs install
USER agent
ENV HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew
ENV PATH="/home/agent/.krew/bin:\
${HOMEBREW_PREFIX}/opt/mysql-client/bin:\
${PATH}"

# Bundled dotfiles & agent configuration
COPY --chown=agent:agent files/home/ /home/agent/

# Make Antigravity detect the environment as remote/SSH.
# This forces the copy/paste OAuth flow instead of attempting
# to launch a browser inside the sandbox.
ENV SSH_CONNECTION="sandbox 0 sandbox 0"

WORKDIR /home/agent/workspace
ENTRYPOINT ["agy"]
CMD ["--dangerously-skip-permissions"]
