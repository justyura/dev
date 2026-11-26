#!/bin/bash
# shellcheck source=scripts/lib/common.sh
source "$HOME/.config/scripts/lib/common.sh"
# shellcheck source=scripts/lib/bar_tokens.sh
source "$SCRIPTS_DIR/lib/bar_tokens.sh"

# 批量更新所有空间指示器（只查询一次 yabai）

space_current_style() {
  local item=$1 drawing=$2
  ARGS+=(--set "$item" drawing="$drawing" icon.color="$COLOR_ON_ACCENT" icon.font="$FONT_TITLE"
    background.drawing=on background.color="$COLOR_ACCENT" background.border_width="$NO_BORDER")
}

space_occupied_style() {
  local item=$1 drawing=${2:-}
  ARGS+=(--set "$item")
  [ -n "$drawing" ] && ARGS+=(drawing="$drawing")
  ARGS+=(icon.color="$COLOR_SUBTEXT" icon.font="$FONT_BODY"
    background.drawing=off background.color="$COLOR_TRANSPARENT" background.border_width="$NO_BORDER")
}

# space_focus.sh 只加载上面的共享样式，不执行状态查询和绘制流程。
[ "${SPACE_STYLES_ONLY:-0}" = 1 ] && return 0

# 悬停事件交给 hover.sh（space.1 挂的是本脚本）
case "$SENDER" in
  mouse.entered | mouse.exited | mouse.exited.global)
    exec "$SCRIPTS_DIR/sketchybar/hover.sh"
    ;;
esac

# Zen 模式开启时这个条目是隐藏的：内容照常更新，但不要把自己重新显示出来（见 plugins/zen.sh）
ZEN_SHOW=on
[ -f "$HOME/.cache/sketchybar/zen_hidden" ] && ZEN_SHOW=off

# 串行执行：多个事件会同时触发本脚本，只让一个实例运行；其余只标记 dirty，
# 运行中的实例会在结束前重新查询一次，保证最后写到栏上的是最新状态
LOCK="$HOME/.cache/sketchybar/space.lock"
DIRTY="$HOME/.cache/sketchybar/space.dirty"
mkdir -p "$HOME/.cache/sketchybar"
touch "$DIRTY"
find "$LOCK" -maxdepth 0 -mmin +1 -exec rmdir {} \; 2>/dev/null # 清理异常退出留下的锁
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

while [ -f "$DIRTY" ]; do
  rm -f "$DIRTY"

  # 一次性获取所有数据：1–10 格对应主屏序号 1–10
  # "有内容"只算普通窗口，不算在所有桌面都显示的浮窗（sticky）和最小化窗口。
  WINS=$(yabai -m query --windows 2>/dev/null || echo '[]')
  STATES=$(yabai -m query --spaces | jq -er --argjson wins "$WINS" '
    if type != "array" then error("spaces must be an array") else . end
    | ([.[] | select(.display == 1)] | sort_by(.index)) as $main
    | [range(1; 11) as $n
       | $main[$n - 1] as $space
       | if $space == null then "missing"
         elif (($space["has-focus"] == true) or ($space["is-visible"] == true)) then "current"
         elif ([$wins[] | select(.space == $space.index and ."is-sticky" == false and ."is-minimized" == false and .subrole == "AXStandardWindow")] | length) > 0 then "occupied"
         else "empty" end]
    | .[]
  ') || continue

  # 构建一条批量 sketchybar 命令（每次都完整设置全部空间：多个事件会并发触发本脚本，
  # 只更新“有变化”的空间会让较晚完成的旧结果覆盖新结果，数字就会错）
  ARGS=()
  i=0
  while IFS= read -r STATE; do
    i=$((i + 1))
    case "$STATE" in
      current)
        space_current_style "space.$i" "$ZEN_SHOW"
        ;;
      occupied)
        space_occupied_style "space.$i" "$ZEN_SHOW"
        ;;
      empty | missing)
        ARGS+=(--set "space.$i" drawing=off background.drawing=off)
        ;;
    esac
  done <<<"$STATES"

  SIGNATURE="${ARGS[*]}"
  PREVIOUS=
  if [ -f "$HOME/.cache/sketchybar/space.rendered" ]; then
    IFS= read -r PREVIOUS <"$HOME/.cache/sketchybar/space.rendered" || :
  fi
  if [ "$SENDER" = forced ] || [ "$SIGNATURE" != "$PREVIOUS" ]; then
    sketchybar "${ARGS[@]}" && printf '%s' "$SIGNATURE" >"$HOME/.cache/sketchybar/space.rendered"
  fi
done
