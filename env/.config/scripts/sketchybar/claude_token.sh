#!/bin/bash

# 为 SketchyBar 取得可用的 Claude Code OAuth access token。access token 约 8 小时后过期，
# 而 Claude Code CLI 不运行时不会自动续期，因此栏的用量请求会长期失败。只有 CLI 未运行、
# 成功取得独占锁、最近 30 分钟没有失败且 refresh token 仍有效时才自行续期；CLI 运行时
# 由 CLI 管理 token，避免双方同时使用一次性 refresh token，导致其中一方被登出。
# 钥匙串拿不到 token 时，退回 Claude 桌面版最新内嵌进程启动时注入的 token。
# 续期与用量接口按 User-Agent 分桶限流，curl、claude-code、浏览器等常见 UA 的桶经常被同一出口 IP
# 的其他流量耗尽（稳定返回 429，掩盖真实的 200/401），所以统一用面板专属 UA；
# 调用方请求用量接口时同样使用 CLAUDE_USER_AGENT。
# 用法：source claude_token.sh；调用 claude_access_token [force]

CLAUDE_TOKEN_SERVICE="Claude Code-credentials"
CLAUDE_TOKEN_URL="https://platform.claude.com/v1/oauth/token"
CLAUDE_TOKEN_CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
CLAUDE_USER_AGENT="dotfiles-panel/1.0 (usage)"

_claude_token_fresh() {
  local credentials=$1 now_ms
  now_ms=$(($(date +%s) * 1000))
  jq -e --argjson threshold "$((now_ms + 300000))" '
    .claudeAiOauth.accessToken as $token
    | .claudeAiOauth.expiresAt as $expires
    | ($token | type == "string" and length > 0)
      and ($expires | type == "number" and . > $threshold)
  ' >/dev/null 2>&1 <<<"$credentials"
}

# 只把使用钥匙串凭证的 CLI 算作“运行中”。Claude 桌面版常驻的内嵌 Claude Code 进程也叫 claude，
# 但由 App 通过 CLAUDE_CODE_OAUTH_TOKEN 注入 token，既不读也不续期钥匙串；若把它们算进来，
# 桌面版开着时钥匙串 token 过期后就永远不会续期。读不到环境变量的进程仍保守地视为 CLI。
_claude_cli_running() {
  local pid command
  for pid in $(pgrep -x claude 2>/dev/null); do
    command=$(ps eww -o command= -p "$pid" 2>/dev/null) || continue
    [ -n "$command" ] || continue
    case "$command" in
      *' CLAUDE_CODE_OAUTH_TOKEN='*) continue ;;
    esac
    return 0
  done
  return 1
}

# 把 ps 的 etime（[[dd-]hh:]mm:ss）换算成秒。
_claude_etime_seconds() {
  local etime=$1 days=0 hours=0 minutes=0 seconds=0 a b c
  case "$etime" in
    *-*)
      days=${etime%%-*}
      etime=${etime#*-}
      ;;
  esac
  IFS=: read -r a b c <<<"$etime"
  if [ -n "$c" ]; then
    hours=$a minutes=$b seconds=$c
  else
    minutes=$a seconds=${b:-0}
  fi
  printf '%s\n' "$((((10#$days * 24 + 10#$hours) * 60 + 10#$minutes) * 60 + 10#$seconds))"
}

# 桌面版启动内嵌 Claude Code 进程时注入当时有效的 token，进程本身不会更新环境变量，
# 所以取最新启动的那个；只用桌面版时它是唯一持续有效的来源。
_claude_desktop_token() {
  local pid command token etime age best_age='' best_token=''
  for pid in $(pgrep -x claude 2>/dev/null); do
    command=$(ps eww -o command= -p "$pid" 2>/dev/null) || continue
    token=$(tr ' ' '\n' <<<"$command" | sed -n 's/^CLAUDE_CODE_OAUTH_TOKEN=//p' | head -n 1)
    [ -n "$token" ] || continue
    etime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ') || continue
    [ -n "$etime" ] || continue
    age=$(_claude_etime_seconds "$etime")
    if [ -z "$best_age" ] || [ "$age" -lt "$best_age" ]; then
      best_age=$age
      best_token=$token
    fi
  done
  [ -n "$best_token" ] || return 1
  printf '%s' "$best_token"
}

_claude_lock_acquire() {
  local lock=$1 lock_pid
  if mkdir "$lock" 2>/dev/null; then
    printf '%s\n' "$$" >"$lock/pid"
    return 0
  fi
  lock_pid=$(cat "$lock/pid" 2>/dev/null || true)
  if [[ "$lock_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
    rm -f "$lock/pid"
    rmdir "$lock" 2>/dev/null || return 1
    mkdir "$lock" 2>/dev/null || return 1
    printf '%s\n' "$$" >"$lock/pid"
    return 0
  fi
  return 1
}

_claude_keychain_token() (
  local force=${1:-} cache_dir lock fail credentials original_token account
  local refresh_expires now_ms refresh_token scopes request response status body
  local expires_in new_expires refresh_expires_in refresh_expires_at new_json

  credentials=$(security find-generic-password -s "$CLAUDE_TOKEN_SERVICE" -w 2>/dev/null) || return 1
  original_token=$(jq -r '.claudeAiOauth.accessToken // empty' <<<"$credentials")
  [ -n "$original_token" ] || return 1
  if [ "$force" != force ] && _claude_token_fresh "$credentials"; then
    printf '%s' "$original_token"
    return 0
  fi

  if _claude_cli_running; then
    printf '%s\n' 'Claude token 已过期：终端 Claude Code 正在运行，交由它续期' >&2
    return 1
  fi
  cache_dir="$HOME/.cache/sketchybar"
  lock="$cache_dir/claude_token_refresh.lock"
  fail="$cache_dir/claude_token_refresh.fail"
  mkdir -p "$cache_dir"
  _claude_lock_acquire "$lock" || return 1
  trap 'rm -f "$lock/pid"; rmdir "$lock" 2>/dev/null' EXIT HUP INT TERM

  # 上锁前 CLI 或另一轮栏刷新可能刚续期；重读后优先使用它的新 token。
  credentials=$(security find-generic-password -s "$CLAUDE_TOKEN_SERVICE" -w 2>/dev/null) || return 1
  if _claude_token_fresh "$credentials"; then
    if [ "$force" != force ] || [ "$(jq -r '.claudeAiOauth.accessToken // empty' <<<"$credentials")" != "$original_token" ]; then
      jq -r '.claudeAiOauth.accessToken' <<<"$credentials"
      return 0
    fi
  fi

  # CLI 可能在第一次检查后刚启动；真正使用一次性 refresh token 前再检查一次。
  _claude_cli_running && return 1
  if [ -f "$fail" ] && [ "$(($(date +%s) - $(stat -f %m "$fail" 2>/dev/null || echo 0)))" -lt 1800 ]; then
    return 1
  fi

  now_ms=$(($(date +%s) * 1000))
  refresh_expires=$(jq -r '.claudeAiOauth.refreshTokenExpiresAt // empty' <<<"$credentials")
  if [ -n "$refresh_expires" ] && ! jq -en --argjson expires "$refresh_expires" --argjson now "$now_ms" \
    '$expires | type == "number" and . > $now' >/dev/null 2>&1; then
    printf '%s\n' 'Claude 登录已过期（refresh token 到期），需在终端运行 claude 后 /login' >&2
    return 1
  fi
  refresh_token=$(jq -r '.claudeAiOauth.refreshToken // empty' <<<"$credentials")
  [ -n "$refresh_token" ] || return 1
  scopes=$(jq -r '.claudeAiOauth.scopes // [] | if type == "array" then join(" ") else tostring end' <<<"$credentials")
  request=$(jq -nc --arg refresh "$refresh_token" --arg client "$CLAUDE_TOKEN_CLIENT_ID" --arg scope "$scopes" \
    '{grant_type:"refresh_token", refresh_token:$refresh, client_id:$client, scope:$scope}')

  response=$(printf '%s' "$request" | curl -sS -m 10 -w '\n%{http_code}' -X POST "$CLAUDE_TOKEN_URL" \
    -A "$CLAUDE_USER_AGENT" -H 'Content-Type: application/json' --data @-) || {
    printf '%s\n' 'Claude token 续期失败：网络错误' >&2
    touch "$fail"
    return 1
  }
  status=${response##*$'\n'}
  body=${response%$'\n'*}
  if [ "$status" != 200 ]; then
    # 错误响应只含错误类型，不含 token，可以写进日志帮助排查。
    printf 'Claude token 续期失败：HTTP %s %s\n' "$status" \
      "$(jq -c '.error // .' <<<"$body" 2>/dev/null | head -c 200)" >&2
    touch "$fail"
    return 1
  fi

  expires_in=$(jq -r '.expires_in // empty' <<<"$body")
  if ! [[ "$expires_in" =~ ^[0-9]+$ ]]; then
    touch "$fail"
    return 1
  fi
  new_expires=$((now_ms + expires_in * 1000))
  refresh_expires_in=$(jq -r '.refresh_token_expires_in // empty' <<<"$body")
  refresh_expires_at=$(jq -r '.refreshTokenExpiresAt // .refresh_token_expires_at // empty' <<<"$body")
  if [[ "$refresh_expires_in" =~ ^[0-9]+$ ]]; then
    refresh_expires_at=$((now_ms + refresh_expires_in * 1000))
  fi
  new_json=$(jq -c --argjson expires "$new_expires" --arg refresh_expires "$refresh_expires_at" '
    .claudeAiOauth.accessToken = ($response.access_token // "")
    | .claudeAiOauth.expiresAt = $expires
    | if (($response.refresh_token // "") | length) > 0
      then .claudeAiOauth.refreshToken = $response.refresh_token else . end
    | if $refresh_expires != "" then .claudeAiOauth.refreshTokenExpiresAt = ($refresh_expires | tonumber) else . end
  ' --argjson response "$body" <<<"$credentials") || {
    touch "$fail"
    return 1
  }
  if ! jq -e '
    (.claudeAiOauth.accessToken | type == "string" and length > 0)
    and (.claudeAiOauth.refreshToken | type == "string" and length > 0)
  ' >/dev/null 2>&1 <<<"$new_json"; then
    touch "$fail"
    return 1
  fi

  account=$(security find-generic-password -s "$CLAUDE_TOKEN_SERVICE" 2>&1 |
    sed -n 's/^[[:space:]]*"acct"<blob>="\(.*\)"$/\1/p' | head -n 1)
  [ -n "$account" ] || {
    touch "$fail"
    return 1
  }
  security add-generic-password -U -s "$CLAUDE_TOKEN_SERVICE" -a "$account" -w "$new_json" >/dev/null 2>&1 || {
    touch "$fail"
    return 1
  }
  rm -f "$fail"
  jq -r '.claudeAiOauth.accessToken' <<<"$new_json"
)

# 先用钥匙串 token（必要时自行续期）；拿不到时退回桌面版内嵌进程的 token。
claude_access_token() {
  _claude_keychain_token "${1:-}" || _claude_desktop_token
}

# 输出钥匙串登录（refresh token）的到期时间，epoch 秒。续期不会延长它，到期后必须重新登录，
# 面板据此提前提醒。没有记录时返回失败。
claude_login_expires_at() {
  security find-generic-password -s "$CLAUDE_TOKEN_SERVICE" -w 2>/dev/null |
    jq -er '.claudeAiOauth.refreshTokenExpiresAt | numbers | . / 1000 | floor' 2>/dev/null
}
