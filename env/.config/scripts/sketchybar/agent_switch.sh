#!/bin/bash
# shellcheck source=scripts/lib/common.sh
source "$HOME/.config/scripts/lib/common.sh"

# option+a 打开 Agent 会话选择器，列表以全屏弹层显示在小屏信息面板上；在 skhd agents 模式中：
# j/k 上下选择，Enter 跳转，Esc 取消；退出时关闭弹层，面板恢复原样。
# 面板没运行时只做选择与跳转，不报错。
# 用法：agent_switch.sh [open|down|up|enter|close]

# skhd 调用时 PATH 很短，tmux 在 Homebrew 目录里。
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
PLUGIN_DIR="$SCRIPTS_DIR/sketchybar"
STATE_DIR="$HOME/.cache/sketchybar"
SEQUENCE="$STATE_DIR/agent_switch_sequence"
SELECTED="$STATE_DIR/agent_switch_selected"
PANEL_SOCKET=${PANEL_TMUX_SOCKET:-panel}
PANEL_RUN="$HOME/.config/panel/bin/panel-run"
AGENT_JUMP=${AGENT_JUMP_BIN:-$PLUGIN_DIR/agent_jump.sh}

panel_tmux() { tmux -L "$PANEL_SOCKET" "$@" 2>/dev/null; }

# 选择列表显示在小屏面板的全屏弹层里（面板页面上没有 Agent 窗格）。
# 弹层里跑 agents 模块的运行器，收到 USR1 立即重画。
panel_refresh_agents() {
  pkill -USR1 -f 'panel-run agents' 2>/dev/null || true
}

panel_show_agents() {
  panel_tmux list-clients | grep -q . || return 0
  panel_tmux display-popup -C
  nohup tmux -L "$PANEL_SOCKET" display-popup -B -E -w 100% -h 100% \
    "exec env -u TMUX_PANE '$PANEL_RUN' agents 30" >/dev/null 2>&1 &
}

panel_restore_page() {
  panel_tmux display-popup -C
}

select_index() {
  local index=$1 total
  [ -s "$SEQUENCE" ] || return 1
  total=$(wc -l <"$SEQUENCE" | tr -d ' ')
  [ "$index" -lt 1 ] && index=$total
  [ "$index" -gt "$total" ] && index=1
  printf '%s\n' "$index" >"$SELECTED.tmp" && mv "$SELECTED.tmp" "$SELECTED"
  panel_refresh_agents
}

case "${1:-open}" in
  open)
    mkdir -p "$STATE_DIR"
    # shellcheck source=scripts/sketchybar/agent_lib.sh
    source "$PLUGIN_DIR/agent_lib.sh"
    agent_session_lines >"$SEQUENCE"
    selected=1
    if [ "$(wc -l <"$SEQUENCE" | tr -d ' ')" -gt 1 ] && [ "$(head -1 "$SEQUENCE" | cut -f7)" = current ]; then
      selected=2
    fi
    printf '%s\n' "$selected" >"$SELECTED"
    panel_show_agents
    ;;
  down)
    select_index $(($(cat "$SELECTED" 2>/dev/null || echo 1) + 1))
    ;;
  up)
    select_index $(($(cat "$SELECTED" 2>/dev/null || echo 1) - 1))
    ;;
  enter)
    index=$(cat "$SELECTED" 2>/dev/null || echo 1)
    file=$(sed -n "${index}p" "$SEQUENCE" 2>/dev/null | cut -f1)
    rm -f "$SELECTED"
    panel_restore_page
    [ -n "$file" ] && exec "$AGENT_JUMP" "$file"
    ;;
  close)
    rm -f "$SELECTED"
    panel_restore_page
    ;;
esac
