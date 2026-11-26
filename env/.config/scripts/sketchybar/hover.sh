#!/bin/bash
# shellcheck source=scripts/lib/common.sh
source "$HOME/.config/scripts/lib/common.sh"

# 悬停高亮：鼠标移入可点击元素时点亮所在组的底块，移出恢复
# 一个组由多个条目拼成（进度条、文字、图标），在成员之间移动会连发 exited/entered，
# 且事件脚本并发执行——所以按成员记录悬停状态，稍等片刻后再按
# “组内是否仍有成员被悬停”统一收敛，避免闪烁
# 也被 standup.sh / ai_usage.sh / space.sh 转调（沿用 sketchybar 传入的 $NAME/$SENDER）

DIR="$HOME/.cache/sketchybar/hover"
mkdir -p "$DIR"

case "$NAME" in
  agents | agents.*)
    GROUP=agents TARGET=""
    ;; # 行自行着色，仅跟踪悬停状态。
  space.*)
    # space 的可见性和强调只由 space.sh 决定，避免悬停让空 space 重现。
    exit 0
    ;;
  *)
    # standup.bar → standup.bracket，claude_usage.pct_5h → claude_usage.bracket
    GROUP=${NAME%%.*} TARGET=${NAME%%.*}.bracket
    REST="background.color=$COLOR_SURFACE background.border_color=$COLOR_SURFACE"
    HOVER="background.color=$COLOR_SURFACE_ALT background.border_color=$COLOR_MUTED"
    ;;
esac

case "$SENDER" in
  mouse.entered) touch "$DIR/$NAME" ;;
  mouse.exited) rm -f "$DIR/$NAME" ;;
  mouse.exited.global) rm -f "$DIR/$GROUP" "$DIR/$GROUP".* ;;
  *) exit 0 ;;
esac

sleep 0.05
[ -n "$TARGET" ] || exit 0

if compgen -G "$DIR/$GROUP" >/dev/null || compgen -G "$DIR/$GROUP.*" >/dev/null; then
  # shellcheck disable=SC2086  # HOVER 包含两个 SketchyBar 属性，必须拆成两个参数。
  sketchybar --animate tanh 8 --set "$TARGET" $HOVER
else
  # shellcheck disable=SC2086  # REST 包含两个 SketchyBar 属性，必须拆成两个参数。
  sketchybar --animate tanh 8 --set "$TARGET" $REST
fi
