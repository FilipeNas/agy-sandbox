#!/usr/bin/env bash
set -Eeuo pipefail
trap 'printf "Image test failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

image="${1:-agy-sandbox:dev}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

printf 'Checking image configuration: %s\n' "$image"
docker image inspect "$image" | jq -e '.[0].Config |
  .User == "agent" and
  .WorkingDir == "/home/agent/workspace" and
  .Entrypoint == ["agy"] and
  .Cmd == ["--dangerously-skip-permissions"]' > /dev/null

docker run --rm -i --network none --entrypoint bash \
  --mount "type=bind,src=$repo_root,dst=/expected,readonly" \
  "$image" -sEeuo pipefail <<'TESTS'
trap 'printf "Container test failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

printf 'Checking sandbox user, environment, and paths\n'
test "$(id -un)" = agent
test "$(id -u)" -ne 0
test "$HOME" = /home/agent
test "$PWD" = /home/agent/workspace
test "$BASH_ENV" = /etc/sandbox-persistent.sh
test "$HOMEBREW_PREFIX" = /home/linuxbrew/.linuxbrew
test "$SSH_CONNECTION" = 'sandbox 0 sandbox 0'
test -w "$HOME"
test -w "$PWD"
test "$(readlink /usr/local/bin/agy)" = /home/agent/.local/bin/agy

printf 'Checking installed tools and CLI versions\n'
tools=(
  agy brew aws awscurl awsdac docker-credential-ecr-login fzf gh git git-lfs
  helm ipcalc jq kubectl-krew kubecolor kubectx kubens kubectl kustomize mysql nano
  nmap tofu pgcli rg stern terraform-docs terragrunt tflint uv websocat yq
  zoxide isort ruff pre-commit docker
)
for tool in "${tools[@]}"; do
  command -v "$tool"
done
test "$(command -v uv)" = /home/linuxbrew/.linuxbrew/bin/uv
test "$(command -v mysql)" = /home/linuxbrew/.linuxbrew/opt/mysql-client/bin/mysql
case ":$PATH:" in
  *:/home/agent/.krew/bin:*) ;;
  *) exit 1 ;;
esac

for tool in agy aws gh git git-lfs jq mysql tofu pgcli rg \
  terraform-docs terragrunt tflint uv isort ruff pre-commit; do
  timeout 30 "$tool" --version
done
timeout 30 helm version --short
timeout 30 kubectl version --client
timeout 30 kubectl krew version
timeout 30 docker compose version
timeout 30 docker buildx version

printf 'Checking offline Git LFS round-trip\n'
test "$(git config --system --get filter.lfs.clean)" = 'git-lfs clean -- %f'
test "$(git config --get filter.lfs.process)" = 'git-lfs filter-process'
test "$(git config --get filter.lfs.required)" = true

lfs_fixture="$(mktemp -d)"
(
  cd "$lfs_fixture"
  git init -q
  printf '*.bin filter=lfs diff=lfs merge=lfs -text\n' > .gitattributes
  printf 'offline LFS smoke test\n' > payload.bin
  git add .gitattributes payload.bin
  git show :payload.bin | grep -F 'version https://git-lfs.github.com/spec/v1'
  git show :payload.bin | git lfs smudge | cmp - payload.bin
)

printf 'Checking dotfiles, agent settings, and staged context\n'
cmp /expected/files/home/.bashrc "$HOME/.bashrc"
cmp /expected/files/home/.gemini/antigravity-cli/settings.json \
  "$HOME/.gemini/antigravity-cli/settings.json"
test "$(stat -c %U "$HOME/.bashrc")" = agent
test "$(stat -c %U "$HOME/.gemini/antigravity-cli/settings.json")" = agent
jq -e '.onboardingComplete and .terms.accepted and
  .toolPermission == "always-proceed" and .agentMode == "accept-edits"' \
  "$HOME/.gemini/antigravity-cli/settings.json" > /dev/null
cmp /expected/context.md /usr/share/sandbox/kit/agy-sandbox/context.md

bash -ic 'set -e; alias kubectl | grep -F kubecolor; type z; test -x "$EDITOR"; command -v ruff'

printf 'Checking kit descriptor and lifecycle hook\n'
descriptor=/usr/share/sandbox/kit/agy-sandbox/kit.yaml
yq -o=json "$descriptor" | jq -e '.schemaVersion == "3" and
  .kind == "workload" and (.provides | index("agy") != null)' > /dev/null
hook="$(yq -r '.capabilities[] | select(.type == "com.docker.sandbox/lifecycle@1") | .config.install[0].command' "$descriptor")"
test -n "$hook"
fixture="$(mktemp -d)"
mkdir -p "$fixture/.gemini/antigravity-cli"
settings="$fixture/.gemini/antigravity-cli/settings.json"
jq '. + {trustedWorkspaces: ["/existing"], smokeTest: "preserve"}' \
  "$HOME/.gemini/antigravity-cli/settings.json" > "$settings"
workspace='/workspace/project with spaces'
for attempt in 1 2; do
  HOME="$fixture" WORKSPACE_DIR="$workspace" bash -euc "$hook"
done
jq -e --arg workspace "$workspace" '.trustedWorkspaces == ["/existing", $workspace] and
  .smokeTest == "preserve" and .agentMode == "accept-edits"' "$settings" > /dev/null
test "$(stat -c %a "$settings")" = 600
rm "$settings"
HOME="$fixture" WORKSPACE_DIR="$workspace" bash -euc "$hook"
jq -e --arg workspace "$workspace" '.trustedWorkspaces == [$workspace]' "$settings" > /dev/null
test "$(stat -c %a "$settings")" = 600
printf 'Image smoke tests passed.\n'
TESTS
