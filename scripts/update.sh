#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root, inside `nix develop`.
test -f source.json
url=https://github.com/WebKit/WebKit.git
rev=$(git ls-remote "$url" refs/heads/main | cut -f1)
[[ "$rev" =~ ^[0-9a-f]{40}$ ]]
if [[ "$rev" == "$(jq -r .rev source.json)" ]]; then
  echo "WebKit is already pinned to $rev"
  exit 0
fi

metadata=$(nix-prefetch-git --quiet --url "$url" --rev "$rev" \
  --sparse-checkout $'Source\nTools\nCMakeLists.txt' --non-cone-mode)
source_path=$(jq -er .path <<< "$metadata")
version=$(sed -nE 's/^SET_PROJECT_VERSION\(([0-9]+) ([0-9]+) ([0-9]+)\)/\1.\2.\3/p' \
  "$source_path/Source/cmake/OptionsGTK.cmake")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]

next=$(mktemp)
trap 'rm -f "$next"' EXIT
jq --arg version "$version" \
  '{version: $version, date: (.date | split("T")[0]), rev, hash}' \
  <<< "$metadata" > "$next"
mv "$next" source.json
