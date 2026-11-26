#!/bin/bash
# shellcheck source=scripts/lib/common.sh
source "$HOME/.config/scripts/lib/common.sh"

# 当前 tmux project 的 Things 进度：项目名 + 已完成/总数
# 点击时间轴弹出 Things 3 中与当前 tmux 会话同名项目的待办清单（未完成 + 今天完成；悬停不自动弹出），
# 左键勾选/取消完成、右键在 Things 中打开该待办（things_toggle.sh）；Things 不在运行时不会主动启动它
# alt+k 进入键盘模式操作该清单（things_nav.sh）；day_timeline.sh render 取数据并生成弹窗行
# 用法：day_timeline.sh [render|refresh]（render 同步生成弹窗行；refresh 在后台刷新变更）

# shellcheck source=sketchybar/settings.sh
source "$HOME/.config/sketchybar/settings.sh"
# shellcheck source=/Users/yura/personal/things/things_lib.sh
source "$HOME/personal/things/things_lib.sh"

PLUGIN_DIR="$SCRIPTS_DIR/sketchybar"
HOVER_DIR="$HOME/.cache/sketchybar/hover"

# 栏上的今日进度使用与 AI 用量共用的 2x 细横条生成器。
progress_image() {
  local percentage=$1 helper="$PLUGIN_DIR/helpers/usage_bars" src="$PLUGIN_DIR/helpers/usage_bars.swift"
  local img="$THINGS_RING_DIR/today_$percentage.png"
  [ -x "$helper" ] && [ "$src" -ot "$helper" ] || swiftc -O "$src" -o "$helper" >/dev/null 2>&1 || return 1
  if [ ! -s "$img" ] || [ "$helper" -nt "$img" ]; then
    mkdir -p "$THINGS_RING_DIR"
    "$helper" "$img.tmp" -1 "$percentage" "$COLOR_ACCENT" "$COLOR_ACCENT" "$COLOR_SURFACE_ALT" progress || return 1
    mv "$img.tmp" "$img" || return 1
  fi
  printf '%s' "$img"
}

# 按一天的起止时间计算当前进度；DAY_TIMELINE_NOW=HH:MM 供测试注入固定时钟。
clock_minutes() {
  local value=$1 hour minute
  case "$value" in
    [0-2][0-9]:[0-5][0-9]) ;;
    *) return 1 ;;
  esac
  hour=${value%:*}
  minute=${value#*:}
  [ "$hour" -le 23 ] || return 1
  printf '%s\n' "$((10#$hour * 60 + 10#$minute))"
}

today_percentage() {
  local now start end elapsed duration
  now=$(clock_minutes "${DAY_TIMELINE_NOW:-$(date +%H:%M)}") || now=0
  start=$(clock_minutes "$DAY_START") || start=0
  end=$(clock_minutes "$DAY_END") || end=1440
  if [ "$end" -le "$start" ]; then
    end=$((end + 1440))
    [ "$now" -ge "$start" ] || now=$((now + 1440))
  fi
  elapsed=$((now - start))
  duration=$((end - start))
  [ "$elapsed" -gt 0 ] || {
    printf '0\n'
    return
  }
  [ "$elapsed" -lt "$duration" ] || {
    printf '100\n'
    return
  }
  printf '%s\n' "$((elapsed * 100 / duration))"
}

hovered() { compgen -G "$HOVER_DIR/timeline" >/dev/null || compgen -G "$HOVER_DIR/timeline.*" >/dev/null; }

render_things() {
  # 取当前 tmux 会话同名项目的待办写入数据文件，再由 things_nav.sh 生成弹窗行（固定宽度、长任务名折行）
  local project todos status=ok
  things_sync_wait        # 等清单上的勾选/调序先写回 Things，否则这里读到的是旧状态
  project=$(view_project) # /xxx 跳转过就取那个项目
  if [ -z "$project" ]; then
    status=NO_SESSION
  else
    todos=$(things_list "$project")
    case "$todos" in NOT_RUNNING | NO_PROJECT)
      status=$todos
      todos=""
      ;;
    esac
  fi
  mkdir -p "$(dirname "$THINGS_ROWS")"
  printf '%s' "${todos:+$todos$'\n'}" >"$THINGS_ROWS"
  echo "$project" >"$THINGS_PROJECT"
  echo "$status" >"$THINGS_STATUS"
  "$HOME/personal/things/things_nav.sh" rebuild
}

# refresh：键盘模式打开后在后台取最新数据；取数据期间若用户已操作过清单（行数据文件被改写），放弃本次结果
refresh_things() {
  local project todos status=ok before
  things_sync_wait
  project=$(view_project)
  before=$(stat -f %m "$THINGS_ROWS" 2>/dev/null)
  if [ -z "$project" ]; then
    status=NO_SESSION
  else
    todos=$(things_list "$project")
    case "$todos" in NOT_RUNNING | NO_PROJECT)
      status=$todos
      todos=""
      ;;
    esac
  fi
  [ -f "$THINGS_NAV" ] || return 0                                       # 已经关闭
  [ "$(stat -f %m "$THINGS_ROWS" 2>/dev/null)" = "$before" ] || return 0 # 期间有勾选/移动等操作
  local new="${todos:+$todos$'\n'}"
  if [ "$new" = "$(cat "$THINGS_ROWS" 2>/dev/null)"$'\n' ] || { [ -z "$new" ] && [ ! -s "$THINGS_ROWS" ]; }; then
    # 数据没变：只在状态变化（如 Loading… → 空清单提示）时刷新
    [ "$status" = "$(cat "$THINGS_STATUS" 2>/dev/null)" ] && return 0
  fi
  printf '%s' "$new" >"$THINGS_ROWS"
  echo "$project" >"$THINGS_PROJECT"
  echo "$status" >"$THINGS_STATUS"
  "$HOME/personal/things/things_nav.sh" rebuild
}

if [ "$1" = render ]; then
  render_things
  exit 0
fi
if [ "$1" = refresh ]; then
  refresh_things
  exit 0
fi

case "$SENDER" in
  mouse.clicked)
    # 点击时间轴：打开/关闭 Things 清单（键盘模式 alt+k 打开时不处理）
    [ -f "$THINGS_NAV" ] && exit 0
    if [ "$(sketchybar --query timeline | jq -r '.popup.drawing')" = on ]; then
      sketchybar --set timeline popup.drawing=off
    else
      echo 0 >"$THINGS_SCROLL"
      things_measure_panel
      render_things
      sketchybar --set timeline popup.drawing=on
    fi
    exit 0
    ;;
  mouse.scrolled)
    # 清单弹窗里滚动：交给 things_nav.sh 移动可见区（弹窗固定行数，超出部分靠滚动查看）
    # shellcheck disable=SC2153  # NAME 和 SCROLL_DELTA 均由 SketchyBar 事件环境注入。
    [[ "$NAME" == timeline.things.* ]] && "$HOME/personal/things/things_nav.sh" scroll "$SCROLL_DELTA"
    exit 0
    ;;
  mouse.entered | mouse.exited | mouse.exited.global)
    # 待办行自身的悬停底色（标题/提示行除外；键盘模式下底色表示光标/选区，不响应悬停）
    # 空行（任务不足一屏时补的占位行）不高亮
    if [[ "$NAME" =~ ^timeline\.things\.line\.[0-9]+$ ]] && [ ! -f "$THINGS_NAV" ] &&
      [ -n "$(sketchybar --query "$NAME" | jq -r '.label.value // empty')" ]; then
      [ "$SENDER" = mouse.entered ] && bg="$COLOR_SURFACE" || bg="$THINGS_ROW_BG"
      sketchybar --set "$NAME" background.color="$bg"
    fi
    "$PLUGIN_DIR/hover.sh"
    # 悬停不自动弹出；点击打开的清单在鼠标离开时间轴和清单后收起
    if ! hovered; then
      [ -f "$THINGS_PIN" ] && exit 0 # 键盘模式打开的清单不随鼠标收起
      # 稍等再收起，方便把鼠标移进弹窗点击
      sleep 0.3
      hovered || sketchybar --set timeline popup.drawing=off
    fi
    exit 0
    ;;
esac

[ "$NAME" = timeline ] || exit 0

PERCENT=$(today_percentage)
sketchybar --set timeline label="今日 ${PERCENT}%" icon.background.image="$(progress_image "$PERCENT")"

PROJECT=$(current_project)
if [ -z "$PROJECT" ]; then
  sketchybar --set timeline.project label="No Project"
  exit 0
fi
sketchybar --set timeline.project label="$PROJECT"
