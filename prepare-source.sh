#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ -e .git ]]; then
    git -c url.https://github.com/.insteadOf=git@github.com: \
        -c url.https://github.com/.insteadOf=ssh://git@github.com/ \
        -c url.https://github.com/.insteadOf=git://github.com/ \
        submodule update --init --recursive
fi

test -f Upstream/TelegramSwift/submodules/telegram-ios/submodules/TelegramVoip/Package.swift
