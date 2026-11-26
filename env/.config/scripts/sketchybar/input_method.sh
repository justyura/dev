#!/bin/bash
# shellcheck source=scripts/lib/common.sh
source "$HOME/.config/scripts/lib/common.sh"

# 输入法状态：中 / 英（鼠须管内部模式，来自 Rime 的 lua/ascii_status.lua）/ US（系统输入法被切到了 U.S.）
# 事件：input_source_change（系统输入法切换通知）、input_method_change（Rime 中英切换时触发）、front_app_switched
# 点击：显示 US 时切回鼠须管；在鼠须管里切换中英（模拟单按右 Control，等同 🌐）

PLUGIN_DIR="$SCRIPTS_DIR/sketchybar"
HELPER_SRC="$SCRIPTS_DIR/sketchybar/helpers/input_source.swift"
HELPER="$SCRIPTS_DIR/sketchybar/helpers/input_source"
RIME_STATE="$HOME/.cache/sketchybar/rime_ascii"
RENDERED="$HOME/.cache/sketchybar/input_method.rendered"
SQUIRREL=im.rime.inputmethod.Squirrel.Hans
AIME=app.zool.inputmethod.aime.hans

WHITE=$COLOR_TEXT
GREY=$COLOR_SUBTEXT
ORANGE=$COLOR_WARNING

case "$SENDER" in
  mouse.entered | mouse.exited | mouse.exited.global)
    exec "$PLUGIN_DIR/hover.sh"
    ;;
esac

if [ ! -x "$HELPER" ] || [ "$HELPER_SRC" -nt "$HELPER" ]; then
  swiftc -O "$HELPER_SRC" -o "$HELPER" >/dev/null 2>&1
fi

current=$("$HELPER" 2>/dev/null)

if [ "$SENDER" = mouse.clicked ]; then
  if [[ "$current" == im.rime.inputmethod.Squirrel* ]]; then
    "$HELPER" tap-right-control
  elif [[ "$current" != app.zool.inputmethod.aime* ]]; then
    "$HELPER" select "$AIME"
  fi
  exit 0 # 状态变化会通过事件再触发本脚本刷新
fi

if [[ "$current" == im.rime.inputmethod.Squirrel* ]]; then
  RIME_ASCII=
  IFS= read -r RIME_ASCII <"$RIME_STATE" 2>/dev/null || :
  if [ "$RIME_ASCII" = 1 ]; then
    LABEL=英
    COLOR=$GREY
  else
    LABEL=中
    COLOR=$WHITE
  fi
elif [[ "$current" == app.zool.inputmethod.aime* ]]; then
  # 韬输入法：不对外广播中英状态，只显示「韬」
  LABEL=韬
  COLOR=$WHITE
else
  LABEL=US
  COLOR=$ORANGE
fi

SIGNATURE="$LABEL|$COLOR"
PREVIOUS=
IFS= read -r PREVIOUS <"$RENDERED" 2>/dev/null || :
if [ "$SENDER" != front_app_switched ] || [ "$SIGNATURE" != "$PREVIOUS" ]; then
  sketchybar --set input_method label="$LABEL" label.color="$COLOR" && printf '%s' "$SIGNATURE" >"$RENDERED"
fi
