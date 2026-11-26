#!/bin/bash
# i3/dwm 式工作区：主屏桌面用 yabai 标签 ws1..ws9 命名，编号不随位置变化。
#   ⌥N 去 wsN，不存在就新建并按编号插到正确位置；中间缺的编号不存在、bar 上也不显示。
# 用法（source 后调用函数）：
#   ws_label_all          给主屏上没标签的桌面补 wsN（优先用它当前的位置号，冲突则取最小空闲号）
#   ws_index N            输出 wsN 当前的桌面序号（不存在则空）
#   ws_ensure N           确保 wsN 存在（必要时新建、打标签、排序），输出其序号
# 固定的内部变量：被别的脚本 source（甚至带临时环境变量）后，函数里依然可用（兼容 set -u）。
WS_YABAI=${YABAI:-/opt/homebrew/bin/yabai}
WS_JQ=${JQ:-/opt/homebrew/bin/jq}
WS_MAP="$HOME/.cache/keyrow/workspaces.json"   # Keyrow 记录的 space id → 编号

ws_label_all() {
  local spaces used idx label n fresh=""
  spaces=$($WS_YABAI -m query --spaces --display 1)
  used=" $($WS_JQ -r '[.[] | .label | select(test("^ws[0-9]+$")) | ltrimstr("ws")] | join(" ")' <<<"$spaces") "
  local map='{}'
  [ -f "$WS_MAP" ] && map=$(cat "$WS_MAP")
  while read -r idx label sid; do
    [[ "$label" =~ ^ws[0-9]+$ ]] && continue
    # yabai 重启会丢标签：优先用 Keyrow 记下的编号，没有记录才按位置编
    n=$($WS_JQ -r --arg sid "$sid" '.[$sid] // empty' <<<"$map")
    [ -n "$n" ] || n=$idx
    if [[ "$used" == *" $n "* ]] || [ "$n" -gt 9 ]; then
      n=1; while [[ "$used" == *" $n "* ]]; do n=$((n + 1)); done
    fi
    $WS_YABAI -m space "$idx" --label "ws$n" 2>/dev/null && used="$used$n " && fresh="$fresh $n"
  done < <($WS_JQ -r 'sort_by(.index)[] | "\(.index) \(if (.label // "") == "" then "-" else .label end) \(.id)"' <<<"$spaces")
  # 新编号的桌面按编号排到正确位置
  for n in $fresh; do ws_sort "$n"; done
}

ws_index() {
  $WS_YABAI -m query --spaces --display 1 | $WS_JQ -r --arg l "ws$1" '.[] | select(.label == $l) | .index' | head -1
}

# 把 wsN 移到正确位置：排在所有编号比它小的工作区之后。
ws_sort() {
  local n=$1 idx want
  idx=$(ws_index "$n"); [ -n "$idx" ] || return 0
  want=$($WS_YABAI -m query --spaces --display 1 | $WS_JQ -r --argjson n "$n" \
    '(sort_by(.index)[0].index) as $first | [.[] | .label | select(test("^ws[0-9]+$")) | ltrimstr("ws") | tonumber | select(. < $n)] | length + $first')
  [ "$idx" = "$want" ] || $WS_YABAI -m space "$idx" --move "$want" 2>/dev/null || true
}

ws_ensure() {
  local n=$1 idx before now
  ws_label_all
  idx=$(ws_index "$n")
  if [ -z "$idx" ]; then
    before=$($WS_YABAI -m query --spaces --display 1 | $WS_JQ length)
    $WS_YABAI -m space --create 1 || return 1
    for _ in $(seq 15); do
      sleep 0.1
      now=$($WS_YABAI -m query --spaces --display 1 | $WS_JQ length)
      [ "$now" -gt "$before" ] && break
    done
    # 新建的桌面在主屏最后，且没有标签
    idx=$($WS_YABAI -m query --spaces --display 1 | $WS_JQ -r 'sort_by(.index) | last | .index')
    $WS_YABAI -m space "$idx" --label "ws$n" || return 1
    ws_sort "$n"
    idx=$(ws_index "$n")
  fi
  printf '%s\n' "$idx"
}
