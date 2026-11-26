#!/bin/bash
# shellcheck source=scripts/lib/common.sh
source "$HOME/.config/scripts/lib/common.sh"

# Zen 模式：栏上只留时钟（点时钟切换 Zen），其余条目全部隐藏（space 由 space.sh 自己按 zen 状态隐藏）。
# 进入时把「当前可见、且不属于保留组」的条目快照进状态文件，退出时只还原快照里的这些 ——
# sketchybarrc 里 input_method.bracket / input_method.gap 本来就是 drawing=off，
# 退出时不能无脑全开。弹窗里的条目（position=popup）一律不动。
# 用法：zen.sh toggle | apply（apply 供 sketchybarrc 重载后恢复状态）

ZEN_STATE="$HOME/.cache/sketchybar/zen_hidden" # 文件存在=zen 开着；内容=被它隐藏的条目名
ZEN_ON_COLOR=$COLOR_SUCCESS                    # 开：强调色
ZEN_OFF_COLOR=$COLOR_BORDER                    # 关：暗色

# 保留组：时钟和它所在的胶囊背景。
keep() {
  case "$1" in
    calendar | capsule.right) return 0 ;;
    *) return 1 ;;
  esac
}

# 当前栏上可见、且不在保留组里的条目（弹窗子项跳过）
hideable() {
  local item info
  for item in $(sketchybar --query bar | jq -r '.items[]'); do
    keep "$item" && continue
    info=$(sketchybar --query "$item" | jq -r '.geometry.position + "|" + .geometry.drawing')
    case "$info" in
      popup\|*) ;;
      *\|on) printf '%s\n' "$item" ;;
    esac
  done
}

set_drawing() { # set_drawing on|off <条目>...
  local state=$1 args=() item
  shift
  for item in "$@"; do args+=(--set "$item" drawing="$state"); done
  [ ${#args[@]} -gt 0 ] && sketchybar "${args[@]}"
}

enter() {
  local items=()
  while IFS= read -r item; do [ -n "$item" ] && items+=("$item"); done < <(hideable)
  mkdir -p "$(dirname "$ZEN_STATE")"
  printf '%s\n' "${items[@]}" >"$ZEN_STATE"
  set_drawing off "${items[@]}"
  sketchybar --set zen icon.color="$ZEN_ON_COLOR"
}

leave() {
  local items=() item
  while IFS= read -r item; do [ -n "$item" ] && items+=("$item"); done <"$ZEN_STATE" 2>/dev/null
  rm -f "$ZEN_STATE"
  set_drawing on "${items[@]}"
  sketchybar --set zen icon.color="$ZEN_OFF_COLOR"
  sketchybar --trigger space_change # zen 期间空间的窗口占用可能变了，让 space.sh 重新校正一次
}

# shellcheck disable=SC2015  # leave 失败时沿用原逻辑执行 enter，以恢复一个确定的 Zen 状态。
case "${1:-toggle}" in
  toggle) [ -f "$ZEN_STATE" ] && leave || enter ;;
  apply)
    # 重载后条目都是可见的：zen 开着就按当前条目重新快照一次，否则只把按钮颜色刷对
    if [ -f "$ZEN_STATE" ]; then enter; else sketchybar --set zen icon.color="$ZEN_OFF_COLOR"; fi
    ;;
esac
