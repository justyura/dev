#!/bin/bash
set -euo pipefail

# 构建并临时签名 Standup Presence 相机在场检测应用。

here=$(cd "$(dirname "$0")" && pwd)
app="$here/StandupPresence.app"
mkdir -p "$app/Contents/MacOS"
swiftc -O "$here/presence.swift" -o "$app/Contents/MacOS/presence"
codesign --force --sign - --identifier local.yura.standup-presence "$app"
