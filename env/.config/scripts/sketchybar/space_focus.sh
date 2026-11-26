#!/bin/bash
# alt+数字 切到主屏第 N 块桌面；shift+alt+数字 把当前窗口移过去并跟过去。0 映射为第 10 块桌面。
# 只用 yabai 原生能力：桌面不存在就什么都不做（不自动新建）。
# 用法：space_focus.sh <1-9|10> [move]
N=$1
YABAI=${YABAI:-/opt/homebrew/bin/yabai}
JQ=${JQ:-/opt/homebrew/bin/jq}
[[ "$N" =~ ^([1-9]|10)$ ]] || exit 1
TARGET=$($YABAI -m query --spaces --display 1 | $JQ -r --argjson n "$N" 'sort_by(.index) | .[$n - 1].index // empty')
[ -n "$TARGET" ] || exit 0
[ "${2:-}" = move ] && $YABAI -m window --space "$TARGET"
$YABAI -m space --focus "$TARGET" 2>/dev/null
exit 0
