#!/bin/bash
# shellcheck source=scripts/lib/common.sh
source "$HOME/.config/scripts/lib/common.sh"
# shellcheck source=scripts/lib/bar_tokens.sh
source "$SCRIPTS_DIR/lib/bar_tokens.sh"
# 自动记录活动时间，并处理休息和历史面板操作。
# 用法：standup.sh [start-break|break|close|history|end-break]

# shellcheck source=sketchybar/settings.sh
source "$HOME/.config/sketchybar/settings.sh"
export STANDUP_WORK_MIN STANDUP_BREAK_MIN STANDUP_IDLE_SEC STANDUP_CAMERA STANDUP_CAMERA_INTERVAL STANDUP_SOUND
ACTION=()
case "$1" in
  start-break)
    ACTION=(start-break)
    SENDER=manual_action
    ;;
  break)
    ACTION=(toggle-break)
    SENDER=manual_action
    ;;
  close)
    sketchybar --set standup popup.drawing=off
    exit 0
    ;;
  history)
    sketchybar --set standup popup.drawing=off
    exec /usr/bin/python3 "$HOME/personal/things/things_now_session.py" report
    ;;
esac
if [ "$SENDER" = mouse.clicked ]; then
  # 触控板普通单击和右键都可开关。
  if [ "$(sketchybar --query standup | jq -r '.popup.drawing')" = on ]; then
    sketchybar --set standup popup.drawing=off
  else
    # 每次生成新文件名，避免 sketchybar 按路径缓存旧图
    NOW=$(date +%s)
    HEATMAP_DIR="$HOME/.cache/sketchybar/heatmap"
    mkdir -p "$HEATMAP_DIR"
    rm -f "$HEATMAP_DIR"/*.png
    IMG="$HEATMAP_DIR/focus-$NOW.png"
    SUMMARY=$(python3 "$SCRIPTS_DIR/sketchybar/focus_heatmap.py" "$FOCUS_DIR" "$IMG" \
      "$FOCUS_HEATMAP_WEEKS" "$FOCUS_LEVEL_HOURS" 2>/dev/null)
    sketchybar --set standup.heatmap.title label="Focus time · last $FOCUS_HEATMAP_WEEKS weeks" \
      --set standup.heatmap background.image="$IMG" \
      --set standup.heatmap.summary label="${SUMMARY:-No focus data yet}" \
      --set standup popup.drawing=on
  fi
  exit 0
fi
case "$SENDER" in
  mouse.entered | mouse.exited | mouse.exited.global)
    "$SCRIPTS_DIR/sketchybar/hover.sh"
    # 允许鼠标越过提醒与历史链接之间的小间隙。
    [ "$SENDER" = mouse.entered ] || sleep 0.35
    if ! compgen -G "$HOME/.cache/sketchybar/hover/standup*" >/dev/null; then
      sketchybar --set standup popup.drawing=off
    fi
    exit 0
    ;;
esac

DATA=$(python3 "$SCRIPTS_DIR/sketchybar/standup_auto.py" "${ACTION[@]}") || exit 0
IFS='|' read -r GLYPH LABEL BREAK_LABEL < <(printf '%s' "$DATA" | jq -r '[.glyph,.label,.break_label] | join("|")')
[ -n "$GLYPH" ] || exit 0
case "$GLYPH" in
  '!') RING_COLOR=$COLOR_WARNING ;;
  'Ⅱ') RING_COLOR=$COLOR_MUTED ;;
  *) RING_COLOR=$COLOR_SUCCESS ;;
esac
RENDERED="$HOME/.cache/sketchybar/standup.rendered"
# SketchyBar 重启后父进程会变化，确保新建条目至少完整渲染一次。
SIGNATURE="$PPID|$GLYPH|$LABEL|$RING_COLOR|$BREAK_LABEL"
PREVIOUS=
IFS= read -r PREVIOUS <"$RENDERED" 2>/dev/null || :
if [ "$SENDER" = forced ] || [ "$SENDER" = manual_action ] || [ "$SENDER" = system_woke ] || [ "$SIGNATURE" != "$PREVIOUS" ]; then
  sketchybar --set standup icon.drawing=off label="$LABEL" label.color="$RING_COLOR" \
    --set standup.bar icon="○" icon.color="$RING_COLOR" background.image="" \
    --set standup.break label="$BREAK_LABEL" && printf '%s' "$SIGNATURE" >"$RENDERED"
fi
[ "$SENDER" = manual_action ] && sketchybar --set standup popup.drawing=off
