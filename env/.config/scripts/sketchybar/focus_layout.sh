#!/bin/bash
# 根据最窄显示器宽度限制主栏的专注任务名。
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
state_dir="$HOME/.cache/focus_bar"
mkdir -p "$state_dir"

# 让固定任务内容使用完整可用宽度，同时为控件预留空间。
chars=$(yabai -m query --displays 2>/dev/null | jq -r '
  ([.[].frame.w] | min // 1200) as $width
  | (($width - 520) / 13 | floor) as $chars
  | if $chars < 12 then 12 elif $chars > 40 then 40 else $chars end
') || exit 0
previous=
IFS= read -r previous <"$state_dir/task_chars" 2>/dev/null || :
[ "$previous" = "$chars" ] && exit 0

bar=/opt/homebrew/bin/sketchybar
if [ ! -x "$bar" ]; then
  bar=$(command -v sketchybar) || exit 0
fi
"$bar" --set focus.task label.max_chars="$chars" scroll_texts=off
printf '%s' "$chars" >"$state_dir/task_chars"
