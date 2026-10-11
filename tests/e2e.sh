#!/usr/bin/env bash
set -Eeuo pipefail
trap 'printf "End-to-end test failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kit="${1:-$repo_root}"
fixture="$(mktemp -d)"
names=()

cleanup() {
  exit_code=$?
  trap - EXIT
  for name in "${names[@]}"; do
    if ! timeout 120 sbx rm --force "$name"; then
      printf 'Cleanup failed for sandbox %s\n' "$name" >&2
      exit_code=1
    fi
  done
  rm -rf "$fixture"
  exit "$exit_code"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
prefix="agy-e2e-$(date +%s)-$$"
mkdir "$fixture/workspace"
git -C "$fixture/workspace" init -q
printf '%s\n' "$prefix" > "$fixture/workspace/host-marker"

mounted="$prefix-mounted"
printf 'Creating mounted sandbox: %s\n' "$mounted"
names+=("$mounted")
timeout 900 sbx create --name "$mounted" --cpus 2 --memory 4g \
  --deny-network example.com "$kit" "$fixture/workspace"
timeout 120 sbx run --detached --name "$mounted"
timeout 180 sbx exec -i "$mounted" bash -sEeuo pipefail <<'MOUNTED'
  trap 'printf "Mounted sandbox test failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

  printf 'Checking agent tools and injected context\n'
  test "$(id -un)" = agent
  agy --version
  command -v kubectl
  command -v ruff
  context="$HOME/AGENTS.md"
  if test -s "$WORKSPACE_DIR/AGENTS.md"; then
    context="$WORKSPACE_DIR/AGENTS.md"
  elif test -s "$(dirname "$WORKSPACE_DIR")/AGENTS.md"; then
    context="$(dirname "$WORKSPACE_DIR")/AGENTS.md"
  fi
  test -s "$context"
  jq -ne --rawfile actual "$context" \
    --rawfile expected /usr/share/sandbox/kit/agy-sandbox/context.md \
    '$actual | contains($expected)'
  printf 'Checking workspace trust and host write-through\n'
  test -n "$WORKSPACE_DIR"
  test -f "$WORKSPACE_DIR/host-marker"
  jq -e --arg workspace "$WORKSPACE_DIR" ".trustedWorkspaces | index(\$workspace) != null" \
    "$HOME/.gemini/antigravity-cli/settings.json"
  test "$(stat -c %a "$HOME/.gemini/antigravity-cli/settings.json")" = 600
  printf "sandbox write\n" > "$WORKSPACE_DIR/sandbox-marker"
  printf 'Checking nested Docker and network policy\n'
  docker info > /dev/null
  docker run --rm alpine:3.23@sha256:85fe1e81d6758c208f3e1eed4338a1997e19d4be002d4dd32d3100c9a8c010a0 echo nested-docker-ok
  curl -fsS --max-time 30 https://docs.docker.com/ -o /dev/null
  if curl -fsS --max-time 15 https://example.com/ -o /dev/null; then
    printf "Network deny rule was not enforced\n" >&2
    exit 1
  fi
MOUNTED
test "$(cat "$fixture/workspace/sandbox-marker")" = 'sandbox write'

mountless="$prefix-mountless"
printf 'Creating mountless sandbox: %s\n' "$mountless"
names+=("$mountless")
timeout 900 sbx create --name "$mountless" --cpus 2 --memory 4g "$kit"
timeout 120 sbx run --detached --name "$mountless"
timeout 120 sbx exec -i "$mountless" bash -sEeuo pipefail <<'MOUNTLESS'
  trap 'printf "Mountless sandbox test failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

  printf 'Checking mountless workspace isolation\n'
  agy --version
  test "$PWD" = /home/agent/workspace
  test ! -e host-marker
  test -w "$PWD"
  test -s "$HOME/AGENTS.md"
  printf "isolated write\n" > isolated-marker
MOUNTLESS
test ! -e "$fixture/workspace/isolated-marker"
printf 'End-to-end sandbox tests passed.\n'
