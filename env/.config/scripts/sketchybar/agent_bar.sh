#!/bin/bash
# shellcheck source=scripts/lib/common.sh
source "$HOME/.config/scripts/lib/common.sh"

# agent 任务（Claude / Codex 图标左侧的一行）：
# - 有待处理会话时显示优先级最高的一个（● 等你处理 / ✓ 已完成 + 会话:窗口），其余计为 +N；点击直接跳到该 tmux 窗格
#   （右侧空间有限，prompt 摘要只在预览里显示）
# - 没有待处理时显示两家合并的运行中计数（"● N running" / "idle"）；点击打开会话列表
# - 右键点击：打开/关闭会话列表（悬停不再自动弹出）
# - agent_bar.sh jump：直接跳到当前显示的那个待处理会话，没有则什么都不做（alt+a 改由 agent_switch.sh 处理）
# 刷新：update_freq 定时 + hook 触发的 agent_status_change 事件

PLUGIN_DIR="$SCRIPTS_DIR/sketchybar"
# shellcheck source=scripts/sketchybar/agent_lib.sh
source "$PLUGIN_DIR/agent_lib.sh"

GREY=$COLOR_MUTED
BLUE=$COLOR_ACCENT
ORANGE=$COLOR_WARNING

pending=()
running=0
while IFS='|' read -r _ _ status _ loc prompt f; do
  case "$status" in
    waiting | done) pending+=("$status|$loc|$prompt|$f") ;;
    running) running=$((running + 1)) ;;
  esac
done < <(agent_rows_all)

if [ ${#pending[@]} -gt 0 ]; then
  sketchybar --set agent.status icon="○" icon.color="$ORANGE" label="${#pending[@]}" label.color="$COLOR_SUBTEXT"
else
  if [ "$running" -gt 0 ]; then
    sketchybar --set agent.status icon="○" icon.color="$BLUE" label="$running" label.color="$COLOR_SUBTEXT"
  else
    sketchybar --set agent.status icon="○" icon.color="$GREY" label="0" label.color="$GREY"
  fi
fi
