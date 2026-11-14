#!/usr/bin/env bash
# Pin the driver cask, and the client headers macos-input builds against, to upstream's latest release.
set -euo pipefail
cd "$(dirname "$0")/.."

repo=pqrs-org/Karabiner-DriverKit-VirtualHIDDevice
cask=Casks/virtual-hid-driver.rb
cmake=clients/macos-input/CMakeLists.txt

tag=$(gh release view --repo "$repo" --json tagName -q .tagName)
version=${tag#v}
current=$(sed -n 's/^  version "\(.*\)"$/\1/p' "$cask")
if [[ $version == "$current" ]]; then
    echo "Already on $version"
    exit 0
fi

pkg="Karabiner-DriverKit-VirtualHIDDevice-$version.pkg"
sha=$(curl -fsSL "https://github.com/$repo/releases/download/$tag/$pkg" | shasum -a 256 | cut -d' ' -f1)
commit=$(gh api "repos/$repo/commits/$tag" -q .sha)

sed -i '' -e "s/^  version \".*\"$/  version \"$version\"/" -e "s/^  sha256 \".*\"$/  sha256 \"$sha\"/" "$cask"
sed -i '' "s/GIT_TAG [0-9a-f]\{40\}/GIT_TAG $commit/" "$cmake"

echo "Driver $current -> $version (commit $commit)"
echo "Docs that mention $current:"
git grep -l -F "$current" -- . ':!Casks' || true
