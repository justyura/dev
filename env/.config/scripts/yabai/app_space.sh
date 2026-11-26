#!/bin/bash
# yabai 信号脚本：让每个 App 有自己的桌面。
#   place    window_created              某 App 的第一个窗口出现 -> 放到本显示器一块空桌面并跳过去；
#                                        没有空桌面就新建一块（打 dyn_ 标签），建不出来就留在当前桌面
#   jump     application_front_switched  切到某个已开的 App（Spotlight / Dock / cmd+tab）-> 跳到它窗口所在的桌面
#   cleanup  window_destroyed / space_changed  任何空桌面离开后即销毁，后面的桌面自动前移补位
# 不处理：有固定桌面规则的 App（规则里 space=^N 自带跳转）、manage=off 的 App、浮动窗口，
# 以及 ANYWHERE_APPS（终端类：开在哪留在哪）。
# 已知：yabai 7.1.25 在 macOS 26.6 arm64 上 `space --create` 静默失效（fork 的 master 已修、未发布），
# 升级后 place 会自动变成真正新建；在那之前靠主屏多留几块空桌面。
# shellcheck disable=SC2016  # $pid、$wid 等是 jq 变量。
set -u
yabai=/opt/homebrew/bin/yabai
jq=/opt/homebrew/bin/jq
ANYWHERE_APPS='^(iTerm2|kitty|Finder)$'
# i3 式固定工作区：应用的新窗口放到对应编号的工作区（不存在就创建），并跟过去。
# 原来在 yabairc 里用 rule space=^N（按位置），工作区按编号后改到这里。
app_ws() {
  # 常驻应用（Keyrow 侧边栏顶部的图标）：各占一个 10 以后的工作区，由 Keyrow 写入映射
  local pinned="$HOME/.cache/keyrow/pinned-ws.tsv" n
  if [ -f "$pinned" ]; then
    n=$(awk -F'\t' -v a="$1" '$1 == a { print $2; exit }' "$pinned")
    [ -n "$n" ] && { echo "$n"; return; }
  fi
  case "$1" in
    Safari) echo 3 ;;
    Claude) echo 4 ;;
    ChatGPT) echo 5 ;;
    Xcode) echo 6 ;;
    "PDF Expert") echo 7 ;;
    InfiniteCanvas) echo 9 ;;
  esac
}

rules=$($yabai -m rule --list 2>/dev/null) || exit 0

# 显示器上第一块空桌面的序号（没有则输出空）
# 桌面里"真正的"窗口：不算全局显示（sticky）的浮窗、最小化窗口和非标准窗口。
# 否则像知行那种在所有桌面都显示的小浮窗会让每个桌面都"不空"，导致每开一个应用就新建一个桌面。
real_windows_jq='[.[] | select(."is-sticky" == false and ."is-minimized" == false and .subrole == "AXStandardWindow")]'
first_empty_space() {
  local wins
  wins=$($yabai -m query --windows)
  $yabai -m query --spaces --display "$1" | $jq -r --argjson wins "$wins" \
    '[.[] | select(."is-native-fullscreen" == false) | .index as $i | select(([$wins[] | select(.space == $i and ."is-sticky" == false and ."is-minimized" == false and .subrole == "AXStandardWindow")] | length) == 0)] | first | .index // empty'
}

# App 名是否命中某类规则：$1=app 名，$2=jq 过滤条件
rule_matches() {
  $jq -e --arg app "$1" "[.[] | select($2) | select(.app != \"\") | select(.app as \$re | \$app | test(\$re))] | length > 0" <<<"$rules" >/dev/null
}

# 两个子命令都跳过：终端类、manage=off 的 App
skip_app() {
  [[ "$1" =~ $ANYWHERE_APPS ]] && return 0
  rule_matches "$1" '.manage == false' && return 0
  return 1
}

case "${1:-}" in
  place)
    wid=${YABAI_WINDOW_ID:?}
    win=$($yabai -m query --windows --window "$wid" 2>/dev/null) || exit 0
    app=$($jq -r .app <<<"$win")
    # 有固定工作区的 App：放到 wsN（不存在就建）并跟过去
    ws=$(app_ws "$app")
    if [ -n "$ws" ]; then
      $jq -e '."is-floating" == false and .role == "AXWindow" and .subrole == "AXStandardWindow"' <<<"$win" >/dev/null || exit 0
      touch "$HOME/.cache/space_focus.lock"
      YABAI=$yabai JQ=$jq source "$HOME/.config/scripts/yabai/ws.sh"
      target=$(ws_ensure "$ws" | tail -1)
      [ -n "$target" ] || exit 0
      $yabai -m window "$wid" --space "$target" && $yabai -m space --focus "$target"
      exit 0
    fi
    skip_app "$app" && exit 0
    rule_matches "$app" '.space > 0' && exit 0
    $jq -e '."is-floating" == false and ."is-minimized" == false and .role == "AXWindow" and .subrole == "AXStandardWindow"' <<<"$win" >/dev/null || exit 0
    pid=$($jq -r .pid <<<"$win")
    space=$($jq -r .space <<<"$win")
    display=$($jq -r .display <<<"$win")
    windows=$($yabai -m query --windows)
    # 不是这个 App 的第一个窗口：不动
    [ "$($jq --argjson pid "$pid" --argjson wid "$wid" '[.[] | select(.pid == $pid and .id != $wid)] | length' <<<"$windows")" -eq 0 ] || exit 0
    # 当前桌面本来就是空的：留下
    [ "$($jq --argjson space "$space" --argjson wid "$wid" '[.[] | select(.space == $space and .id != $wid and ."is-minimized" == false)] | length' <<<"$windows")" -gt 0 ] || exit 0
    target=$(first_empty_space "$display")
    if [ -z "$target" ]; then
      before=$($yabai -m query --spaces | $jq length)
      $yabai -m space --create "$display" 2>/dev/null || true
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        sleep 0.2
        [ "$($yabai -m query --spaces | $jq length)" -gt "$before" ] && break
      done
      target=$(first_empty_space "$display")
      [ -n "$target" ] || exit 0
      # i3 式工作区：新桌面取最小的空闲编号 wsN（bar 和 ⌥N 按标签找桌面）
      YABAI=$yabai JQ=$jq source "$HOME/.config/scripts/yabai/ws.sh" && ws_label_all
    fi
    $yabai -m window "$wid" --space "$target" && $yabai -m space --focus "$target"
    ;;
  jump)
    # 只跟随用户亲手触发的切换：最近 1 秒内没有键盘/鼠标输入，说明是后台应用自己抢了前台，不跳。
    idle_ns=$(ioreg -c IOHIDSystem -d 4 | awk '/HIDIdleTime/ {print $NF; exit}')
    [ -n "$idle_ns" ] && [ "$idle_ns" -gt 1000000000 ] && exit 0
    pid=${YABAI_PROCESS_ID:?}
    windows=$($yabai -m query --windows)
    app=$($jq -r --argjson pid "$pid" 'first(.[] | select(.pid == $pid)) | .app // empty' <<<"$windows")
    [ -n "$app" ] || exit 0
    skip_app "$app" && exit 0
    current=$($yabai -m query --spaces --space | $jq -r .index)
    # 当前桌面已经有它的窗口：不动
    $jq -e --argjson pid "$pid" --argjson cur "$current" '[.[] | select(.pid == $pid and .space == $cur and ."is-minimized" == false)] | length > 0' <<<"$windows" >/dev/null && exit 0
    display=$($yabai -m query --displays --display | $jq -r .index)
    # 优先当前显示器上的窗口，其次任意一个
    read -r target target_space < <($jq -r --argjson pid "$pid" --argjson d "$display" '[.[] | select(.pid == $pid and ."is-minimized" == false and .subrole == "AXStandardWindow")] | (map(select(.display == $d)) + .) | first | select(. != null) | "\(.id) \(.space)"' <<<"$windows")
    [ -n "${target:-}" ] || exit 0
    # window --focus 不会跨桌面切换，先切桌面再聚焦窗口
    $yabai -m space --focus "$target_space" 2>/dev/null
    $yabai -m window --focus "$target"
    ;;
  cleanup)
    # 离开即回收：只回收"刚离开"的那个桌面（space_changed 会带上 YABAI_RECENT_SPACE_ID），
    # 关窗口（window_destroyed）时才扫一遍所有空桌面。删除后 macOS 自动前移补位，编号始终连续。
    # ⌥数字正在新建/切换桌面时（3 秒内有 space_focus 锁）不回收，避免把刚建好的目标删掉。
    lock="$HOME/.cache/space_focus.lock"
    if [ -e "$lock" ] && [ $(( $(date +%s) - $(stat -f %m "$lock") )) -lt 3 ]; then exit 0; fi
    wins=$($yabai -m query --windows)
    spaces=$($yabai -m query --spaces)
    only=""
    if [ -n "${YABAI_RECENT_SPACE_ID:-}" ]; then
      only=$($jq -r --argjson id "$YABAI_RECENT_SPACE_ID" '.[] | select(.id == $id) | .index' <<<"$spaces")
      [ -n "$only" ] || exit 0
    fi
    $jq -r --argjson wins "$wins" --arg only "$only" '
      group_by(.display)[] | (length) as $n |
      [.[] | .index as $i
           | select($only == "" or ($i | tostring) == $only)
           | select(."is-visible" == false and ."has-focus" == false and ."is-native-fullscreen" == false)
           | select(([$wins[] | select(.space == $i and ."is-sticky" == false and ."is-minimized" == false and .subrole == "AXStandardWindow")] | length) == 0)
           | .index] | .[0:($n - 1)][]' <<<"$spaces" |
      sort -rn | while read -r idx; do $yabai -m space --destroy "$idx" 2>/dev/null || true; done
    ;;
  *)
    printf 'usage: %s {place|jump|cleanup}\n' "$0" >&2
    exit 2
    ;;
esac
