#!/bin/bash
# shellcheck source=scripts/lib/common.sh
source "$HOME/.config/scripts/lib/common.sh"

# Claude / Codex 各自的紧凑状态徽标，显示在对应 app 图标旁。
# 状态优先级：等待处理 > 已完成待查看 > 运行中 > 空闲。

PLUGIN_DIR="$SCRIPTS_DIR/sketchybar"
# shellcheck source=scripts/sketchybar/agent_lib.sh
source "$PLUGIN_DIR/agent_lib.sh"

case "$NAME" in
  claude_usage.logo) provider=claude ;;
  codex_usage.logo) provider=codex ;;
  *) exit 0 ;;
esac

running=0
waiting=0
done=0
target=""

while IFS='|' read -r _ _ status _ _ _ file; do
  [ -n "$file" ] || continue
  case "$status" in
    running) running=$((running + 1)) ;;
    waiting) waiting=$((waiting + 1)) ;;
    done) done=$((done + 1)) ;;
    *) continue ;;
  esac
  [ -n "$target" ] || target=$file
done < <(agent_rows "$provider")

total=$((running + waiting + done))
if [ "$SENDER" = mouse.clicked ]; then
  if [ "$BUTTON" = right ]; then
    usage="${provider}_usage"
    [ "$(sketchybar --query "$usage" | jq -r '.popup.drawing')" = on ] && next=off || next=on
    sketchybar --set "$usage" popup.drawing="$next"
    exit 0
  elif [ -n "$target" ]; then
    exec "$PLUGIN_DIR/agent_jump.sh" "$target"
  fi
fi

[ "$provider" = claude ] && short=Cl || short=Cx
sketchybar --set "$NAME" label="$short ✓$total" label.color="$COLOR_SUBTEXT"
