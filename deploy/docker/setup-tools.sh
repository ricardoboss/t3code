#!/bin/bash
set -euo pipefail
umask 077
export PATH="$HOME/.local/bin:$PATH"
export NPM_CONFIG_PREFIX="$HOME/.local"

# Add tools here and their native authentication commands in authenticate().
tools=(gh codex claude opencode)
labels=('GitHub CLI' 'Codex' 'Claude Code' 'OpenCode')
packages=('' '@openai/codex' '@anthropic-ai/claude-code' 'opencode-ai')
versions=("${GH_VERSION:-}" "${CODEX_VERSION:-}" "${CLAUDE_VERSION:-}" "${OPENCODE_VERSION:-}")

install_tool() {
  local index=$1 version=$2 tool=${tools[$1]}
  if [[ -z "$version" ]]; then
    echo "Missing image version for $tool; rebuild the image first." >&2
    return 1
  fi
  if [[ "$tool" == gh ]]; then
    install-forge-cli gh "$version" || return
  else
    # Approve only this provider's native binary installation scripts.
    npm install --global --allow-scripts="${packages[$index]}" \
      "${packages[$index]}@$version" || return
  fi
  hash -r
  "$tool" --version
}

authenticate() {
  local tool=$1 method key
  echo 'Complete the CLI prompts below. Open printed login URLs on your own device.'
  case "$tool" in
    gh)
      gh auth login --hostname "${GH_HOST:-github.com}" --web --git-protocol https || return
      gh auth setup-git --hostname "${GH_HOST:-github.com}"
      ;;
    codex)
      printf 'Codex login: 1) ChatGPT device login  2) API key [1]: '
      read -r method || return
      case "${method:-1}" in
        1) codex login --device-auth ;;
        2)
          read -r -s -p 'OpenAI API key (hidden): ' key || return
          printf '\n'
          if [[ -z "$key" ]]; then echo 'No key entered.' >&2; return 1; fi
          printf '%s' "$key" | codex login --with-api-key
          ;;
        *) echo 'Invalid login method.' >&2; return 1 ;;
      esac
      ;;
    claude)
      printf 'Claude login: 1) Claude subscription  2) Console / API billing [1]: '
      read -r method || return
      case "${method:-1}" in
        1) claude auth login --claudeai ;;
        2) claude auth login --console ;;
        *) echo 'Invalid login method.' >&2; return 1 ;;
      esac
      ;;
    opencode) opencode auth login ;;
  esac
}

auth_status() {
  case "$1" in
    gh) gh auth status --hostname "${GH_HOST:-github.com}" ;;
    codex) codex login status ;;
    claude) claude auth status --text ;;
    opencode) opencode auth list ;;
  esac
}

logout() {
  case "$1" in
    gh) gh auth logout --hostname "${GH_HOST:-github.com}" ;;
    codex) codex logout ;;
    claude) claude auth logout ;;
    opencode) opencode auth logout ;;
  esac
}

configure_tool() {
  local index=$1 action=$2 tool=${tools[$1]} version
  printf '\n--- %s ---\n' "${labels[$index]}"
  case "$action" in
    1)
      if ! command -v "$tool" >/dev/null 2>&1; then
        install_tool "$index" "${versions[$index]}" || return
      fi
      authenticate "$tool"
      ;;
    2|4)
      if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool is not installed." >&2
        return 1
      fi
      if [[ "$action" == 2 ]]; then auth_status "$tool"; else logout "$tool"; fi
      ;;
    3)
      version=latest
      if [[ "$tool" == gh ]]; then version=${versions[$index]}; fi
      printf 'Version to install for %s [%s]: ' "$tool" "$version"
      local requested
      read -r requested || return
      install_tool "$index" "${requested:-$version}"
      ;;
  esac
}

echo 'T3 environment tool setup'
echo 'Credentials and tools persist in the home volume and are accessible to agents.'
echo 'Setup signs in again even if already authenticated. Ctrl+C exits.'
while true; do
  printf '\nChoose tools (space-separated numbers, a = all, q = quit):\n'
  for index in "${!tools[@]}"; do
    state='not installed'
    if command -v "${tools[$index]}" >/dev/null 2>&1; then state=installed; fi
    printf '  %s) %s (%s)\n' "$((index + 1))" "${labels[$index]}" "$state"
  done
  read -r -p '> ' selection || exit 0
  case "$selection" in q|Q) exit 0 ;; a|A) selection='1 2 3 4' ;; esac
  read -r -a selected <<< "$selection"
  if [[ ${#selected[@]} == 0 ]]; then continue; fi
  valid=true
  for number in "${selected[@]}"; do
    if [[ ! "$number" =~ ^[1-4]$ ]]; then valid=false; fi
  done
  if [[ "$valid" == false ]]; then echo 'Select numbers 1–4, a, or q.'; continue; fi
  printf '\n1) Set up / reauthenticate  2) Authentication status\n3) Install / update version  4) Log out  0) Back\n'
  read -r -p 'Action [1]: ' action || exit 0
  action=${action:-1}
  case "$action" in 0) continue ;; 1|2|3|4) ;; *) echo 'Invalid action.'; continue ;; esac
  for number in "${selected[@]}"; do
    if ! configure_tool "$((number - 1))" "$action"; then
      echo "${labels[$((number - 1))]} did not complete; you can retry from the menu." >&2
    fi
  done
done
