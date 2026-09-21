#!/bin/sh
set -eu

new_commit=$1
upstream_url=https://github.com/kubernetes-sigs/node-local-dns.git
current_commit=$(tr -d '\n' < COMMIT)
current_version=$(tr -d '\n' < VERSION)
current_base=${current_version%-r*}
current_revision=${current_version##*-r}

if ! printf '%s\n' "$current_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-r[1-9][0-9]*$'; then
    echo "VERSION must have the form <semver>-rN: $current_version" >&2
    exit 1
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT HUP INT TERM

git clone --quiet --filter=blob:none --no-checkout "$upstream_url" "$workdir"
git -C "$workdir" fetch --quiet origin "$new_commit"
upstream_tag=$(git -C "$workdir" describe --tags --match '[0-9]*' --abbrev=0 "$new_commit")

if ! printf '%s\n' "$upstream_tag" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Nearest upstream tag is not a semantic version: $upstream_tag" >&2
    exit 1
fi

if [ "$upstream_tag" != "$current_base" ]; then
    printf '%s-r1\n' "$upstream_tag"
elif [ "$new_commit" != "$current_commit" ]; then
    printf '%s-r%s\n' "$upstream_tag" "$((current_revision + 1))"
else
    printf '%s\n' "$current_version"
fi