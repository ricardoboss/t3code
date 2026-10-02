#!/bin/sh
set -eu

tool=${1:?Usage: install-forge-cli gh VERSION}
version=${2:?Supply a release version without the v prefix}
case "$version" in ''|*[!0-9.]*) echo 'Expected a numeric release version' >&2; exit 1 ;; esac
case "$(uname -m)" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; *) exit 1 ;; esac
destination="$HOME/.local/bin"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cd "$staging"
mkdir -p "$destination"

case "$tool" in
  gh)
    asset="gh_${version}_linux_${arch}.tar.gz"
    release="https://github.com/cli/cli/releases/download/v${version}"
    curl -fsSL "$release/$asset" -o "$asset"
    curl -fsSL "$release/gh_${version}_checksums.txt" -o checksums.txt
    ;;
  *) echo 'Supported tool: gh' >&2; exit 1 ;;
esac

awk -v asset="$asset" '{ name=$2; sub(/^\*/, "", name); if (name==asset) print }' checksums.txt > selected.sha256
test -s selected.sha256
sha256sum -c selected.sha256
tar -xzf "$asset"
executable="gh_${version}_linux_${arch}/bin/gh"
# Replace atomically so updating a running CLI does not truncate its executable.
install -m 0755 "$executable" "$destination/.$tool.new"
mv -f "$destination/.$tool.new" "$destination/$tool"
"$destination/$tool" --version
