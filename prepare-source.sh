#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
root="$PWD"
source_dir="$root/Upstream/TelegramSwift"
commit=38309ec95e59be3958d1e6fe9be331d72527a38d
upstream=https://github.com/TelegramMessenger/telegram-macos.git

if [[ ! -e "$source_dir" ]]; then
    mkdir -p "$root/Upstream"
    checkout=$(mktemp -d "$root/Upstream/.echogram-checkout.XXXXXX")
    trap 'rm -rf "$checkout"' EXIT
    git -C "$checkout" init --quiet
    git -C "$checkout" remote add origin "$upstream"
    git -C "$checkout" fetch --depth 1 origin "$commit"
    git -C "$checkout" checkout --quiet --detach FETCH_HEAD
    mv "$checkout" "$source_dir"
    trap - EXIT
fi

if [[ ! -e "$source_dir/.git" || "$(git -C "$source_dir" rev-parse HEAD)" != "$commit" ]]; then
    printf 'Expected Telegram for macOS at revision %s in %s\n' "$commit" "$source_dir" >&2
    exit 1
fi

if ! git -C "$source_dir" apply --reverse --check "$root/echogram.patch" 2>/dev/null; then
    git -C "$source_dir" apply "$root/echogram.patch"
fi

git -C "$source_dir" \
    -c url.https://github.com/.insteadOf=git@github.com: \
    -c url.https://github.com/.insteadOf=ssh://git@github.com/ \
    -c url.https://github.com/.insteadOf=git://github.com/ \
    submodule update --init --recursive
