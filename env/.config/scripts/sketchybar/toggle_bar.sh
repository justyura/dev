#!/bin/sh
# 切换顶部 SketchyBar 的显隐（alt+w）。状态写在 /tmp，sketchybarrc 重载时据此恢复。

state_file="/tmp/yabai_top_padding_hidden"

if [ -f "$state_file" ]; then
  rm "$state_file"
  sketchybar --bar hidden=false
  sketchybar --update
else
  touch "$state_file"
  sketchybar --bar hidden=true
fi
