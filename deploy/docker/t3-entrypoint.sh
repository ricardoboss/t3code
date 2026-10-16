#!/bin/sh
set -eu

runtime="$T3CODE_HOME/runtime"
state="$runtime/service-state.json"
if [ ! -f "$state" ]; then
    version=$(cat /opt/t3/version)
    mkdir -p "$runtime/versions"
    staging=$(mktemp -d "$runtime/versions/.seed-XXXXXX")
    trap 'rm -rf "$staging"' EXIT
    cp -a /opt/t3/. "$staging/"
    printf '%s\n' "$version" > "$staging/.install-complete"
    if [ ! -d "$runtime/versions/$version" ]; then
        mv "$staging" "$runtime/versions/$version"
    fi
    rm -rf "$staging"
    trap - EXIT
    jq -n --arg version "$version" '{protocol: 3, activeVersion: $version}' > "$runtime/.service-state.tmp"
    mv "$runtime/.service-state.tmp" "$state"
fi

# Resolve the active runtime on every invocation, including after a UI update.
version=$(jq -er '.activeVersion | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+([-+][0-9A-Za-z.+-]+)?$"))' "$state")
executable="$runtime/versions/$version/t3"
if [ "$(cat "$runtime/versions/$version/.install-complete")" != "$version" ]; then
    echo "Incomplete T3 runtime: $version" >&2
    exit 1
fi

if [ "$#" -eq 0 ]; then
    set -- __service-launcher
fi
exec "$executable" "$@"
