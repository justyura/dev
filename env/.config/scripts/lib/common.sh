#!/bin/bash

# 提供配置目录、脚本目录和当前主题的共享常量。
# 用法：在每个需要这些常量的脚本开头 source "$HOME/.config/scripts/lib/common.sh"。
# shellcheck disable=SC2034  # 本文件是共享库，常量由 source 它的调用脚本使用。

# 不使用 CONFIG_DIR：SketchyBar 会注入同名变量，并将它设为 ~/.config/sketchybar。
DOTFILES_CONFIG_DIR="${DOTFILES_CONFIG_DIR:-$HOME/.config}"
SCRIPTS_DIR="$DOTFILES_CONFIG_DIR/scripts"

# 只替换 SketchyBar 颜色值中的 alpha；参数无效时不输出并返回失败。
color_alpha() {
  if [ "$#" -ne 2 ]; then
    return 1
  fi

  local color=$1
  local alpha=$2
  if [ "${#color}" -ne 10 ] || [ "${color#0x}" = "$color" ] || [ "${#alpha}" -ne 2 ]; then
    return 1
  fi
  case "${color#0x}$alpha" in
    *[!0-9a-fA-F]*) return 1 ;;
  esac

  printf '0x%s%s\n' "$alpha" "${color#????}"
}

# 主题固定为 Tokyo Night Storm（不再支持切换）。
DOTFILES_THEME_NAME=tokyo-night-storm
# shellcheck source=scripts/lib/themes/tokyo-night-storm.sh
source "$SCRIPTS_DIR/lib/themes/tokyo-night-storm.sh"

COLOR_TRANSPARENT=0x00000000
