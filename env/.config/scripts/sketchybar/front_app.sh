#!/bin/bash

# 显示当前前台应用，并在 Zen 模式下保持隐藏状态。

# Zen 模式开启时这个条目是隐藏的：内容照常更新，但不要把自己重新显示出来（见 plugins/zen.sh）
ZEN_SHOW=on
[ -f "$HOME/.cache/sketchybar/zen_hidden" ] && ZEN_SHOW=off

# $INFO 由 front_app_switched 事件自动传入
APP_NAME="$INFO"
APP_IMAGE="$INFO"

# 空桌面时 macOS 默认聚焦 Finder，检查是否有实际窗口
if [[ "$APP_NAME" == "Finder" ]] && ! yabai -m query --windows --window &>/dev/null; then
  # 空桌面仍保留位置，避免下方内容移动。
  sketchybar --set front_app drawing=$ZEN_SHOW icon.background.image.drawing=off
  exit 0
fi

case "$APP_NAME" in
  "Google Chrome") APP_NAME="Chrome" ;;
  "Microsoft Edge") APP_NAME="Edge" ;;
  "Visual Studio Code") APP_NAME="VS Code" ;;
  "IntelliJ IDEA") APP_NAME="IntelliJ" ;;
  "System Preferences") APP_NAME="Settings" ;;
  "Sublime Text") APP_NAME="Sublime" ;;
  "iTerm2") APP_NAME="iTerm" ;;
  "WezTerm") APP_NAME="Wez" ;;
esac

if [[ ${#APP_NAME} -gt 20 ]]; then
  APP_NAME="${APP_NAME:0:17}..."
fi

[ -n "$APP_IMAGE" ] || exit 0
sketchybar --set front_app drawing=$ZEN_SHOW icon.background.image.drawing=on icon.background.image="app.$APP_IMAGE"
