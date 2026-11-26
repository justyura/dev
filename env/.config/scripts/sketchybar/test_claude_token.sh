#!/bin/bash
set -euo pipefail

# 用假 security、curl、pgrep 和 ps 验证 Claude token 续期，不读取真实钥匙串，也不访问 OAuth 接口。
# 用法：bash scripts/sketchybar/test_claude_token.sh

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/claude-token-test.XXXXXX")
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM
FAKE_BIN="$TEST_TMP/bin"
mkdir -p "$FAKE_BIN"

fail() {
  printf '失败：%s\n' "$1" >&2
  exit 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "$3（实际：$1，预期：$2）"
}

count() {
  cat "$1" 2>/dev/null || printf '0\n'
}

cat >"$FAKE_BIN/security" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "$1" = find-generic-password ]; then
  for arg in "$@"; do
    if [ "$arg" = -w ]; then
      reads=$(cat "$FAKE_DIR/security_reads" 2>/dev/null || printf '0\n')
      reads=$((reads + 1))
      printf '%s\n' "$reads" >"$FAKE_DIR/security_reads"
      if [ "$reads" -ge 2 ] && [ -f "$FAKE_DIR/credentials_second" ]; then
        cat "$FAKE_DIR/credentials_second"
      else
        cat "$FAKE_DIR/credentials"
      fi
      exit 0
    fi
  done
  printf '    "acct"<blob>="test-account"\n' >&2
  exit 0
fi
if [ "$1" = add-generic-password ]; then
  shift
  account=
  password=
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -a)
        account=$2
        shift 2
        ;;
      -w)
        password=$2
        shift 2
        ;;
      *) shift ;;
    esac
  done
  printf '%s' "$account" >"$FAKE_DIR/written_account"
  printf '%s' "$password" >"$FAKE_DIR/written_json"
  printf '%s' "$password" >"$FAKE_DIR/credentials"
  exit 0
fi
exit 1
EOF

cat >"$FAKE_BIN/pgrep" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${FAKE_CLAUDE_RUNNING:-0}" = 1 ]; then
  printf '111\n12345\n222\n'
  exit 0
fi
exit 1
EOF

# 进程 12345 最新启动；111、222 更早，模拟桌面版里 token 已过期的旧进程。
cat >"$FAKE_BIN/ps" <<'EOF'
#!/bin/bash
set -euo pipefail
pid=
field=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -p)
      pid=$2
      shift 2
      ;;
    -o)
      field=$2
      shift 2
      ;;
    *) shift ;;
  esac
done
if [ "$field" = etime= ]; then
  case "$pid" in
    111) printf '%s\n' ' 2-03:04:05' ;;
    222) printf '%s\n' '   01:00:00' ;;
    *) printf '%s\n' '      05:00' ;;
  esac
  exit 0
fi
if [ "${FAKE_CLAUDE_ENV_TOKEN:-0}" = 1 ]; then
  printf 'claude --output-format stream-json HOME=/fake CLAUDE_CODE_OAUTH_TOKEN=fake-env-%s\n' "$pid"
else
  printf '%s\n' 'claude HOME=/fake'
fi
EOF

cat >"$FAKE_BIN/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
kind=usage
printf '%s\n' "$@" >"$FAKE_DIR/curl_argv"
for arg in "$@"; do
  case "$arg" in
    https://platform.claude.com/v1/oauth/token) kind=token ;;
  esac
done
if [ "$kind" = token ]; then
  cat >"$FAKE_DIR/curl_stdin"
  calls=$(cat "$FAKE_DIR/token_calls" 2>/dev/null || printf '0\n')
  printf '%s\n' "$((calls + 1))" >"$FAKE_DIR/token_calls"
  case "${FAKE_TOKEN_MODE:-success}" in
    success)
      printf '%s\n200' '{"access_token":"fake-new-access","refresh_token":"fake-new-refresh","expires_in":3600,"refresh_token_expires_in":7200}'
      ;;
    missing_access)
      printf '%s\n200' '{"refresh_token":"fake-new-refresh","expires_in":3600}'
      ;;
    no_refresh_expiry)
      printf '%s\n200' '{"access_token":"fake-new-access","refresh_token":"fake-new-refresh","expires_in":3600}'
      ;;
    fail)
      printf '%s\n500' '{"error":"temporarily_unavailable"}'
      ;;
  esac
  exit 0
fi
calls=$(cat "$FAKE_DIR/usage_calls" 2>/dev/null || printf '0\n')
calls=$((calls + 1))
printf '%s\n' "$calls" >"$FAKE_DIR/usage_calls"
if [ "${FAKE_USAGE_401_FIRST:-0}" = 1 ] && [ "$calls" -eq 1 ]; then
  printf '%s\n401' '{"error":"unauthorized"}'
elif [ "${FAKE_USAGE_429:-0}" = 1 ]; then
  # ai_fetch 用 -w '\n%{http_code} %header{retry-after}'，最后一行带 Retry-After。
  printf '%s\n429 %s' '{"error":{"type":"rate_limit_error"}}' "${FAKE_RETRY_AFTER:-}"
else
  printf '%s\n200' '{"five_hour":{"utilization":10,"resets_at":4102444800},"seven_day":{"utilization":20,"resets_at":4102444800}}'
fi
EOF

cat >"$FAKE_BIN/sketchybar" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$FAKE_BIN/claude" <<'EOF'
#!/bin/bash
printf '%s\n' '{"loggedIn":true}'
EOF
chmod +x "$FAKE_BIN/security" "$FAKE_BIN/pgrep" "$FAKE_BIN/ps" "$FAKE_BIN/curl" "$FAKE_BIN/sketchybar" "$FAKE_BIN/claude"
export PATH="$FAKE_BIN:$PATH"

# shellcheck source=scripts/sketchybar/claude_token.sh
source "$ROOT/scripts/sketchybar/claude_token.sh"

reset_case() {
  FAKE_DIR="$TEST_TMP/$1"
  HOME="$FAKE_DIR/home"
  export FAKE_DIR HOME
  unset FAKE_CLAUDE_RUNNING FAKE_CLAUDE_ENV_TOKEN FAKE_TOKEN_MODE FAKE_USAGE_401_FIRST FAKE_USAGE_429 FAKE_RETRY_AFTER
  mkdir -p "$HOME/.cache/sketchybar"
}

credentials_json() {
  jq -nc --arg access "$1" --arg refresh "$2" --argjson expires "$3" --argjson refresh_expires "$4" '
    {claudeAiOauth:{accessToken:$access,refreshToken:$refresh,expiresAt:$expires,
      refreshTokenExpiresAt:$refresh_expires,scopes:["user:profile","user:inference"],
      rateLimitTier:"tier-test",subscriptionType:"pro",keptField:{nested:true}},topLevel:"keep"}
  '
}

NOW_MS=$(($(date +%s) * 1000))
FRESH=$((NOW_MS + 3600000))
EXPIRED=$((NOW_MS - 1000))
REFRESH_FRESH=$((NOW_MS + 7200000))
REFRESH_EXPIRED=$((NOW_MS - 1000))

reset_case fresh
credentials_json fake-old-access fake-old-refresh "$FRESH" "$REFRESH_FRESH" >"$FAKE_DIR/credentials"
out=$(claude_access_token 2>"$FAKE_DIR/stderr") || fail '未过期 token 应可直接读取'
assert_eq "$out" fake-old-access '未过期 token 输出错误'
assert_eq "$(count "$FAKE_DIR/token_calls")" 0 '未过期 token 不应续期'

reset_case running
credentials_json fake-old-access fake-old-refresh "$EXPIRED" "$REFRESH_FRESH" >"$FAKE_DIR/credentials"
export FAKE_CLAUDE_RUNNING=1
if claude_access_token >"$FAKE_DIR/stdout" 2>"$FAKE_DIR/stderr"; then
  fail 'CLI 运行时，过期 token 应返回失败'
fi
assert_eq "$(count "$FAKE_DIR/token_calls")" 0 'CLI 运行时不应续期'

reset_case desktop_token
credentials_json fake-old-access fake-old-refresh "$EXPIRED" "$REFRESH_FRESH" >"$FAKE_DIR/credentials"
export FAKE_CLAUDE_RUNNING=1 FAKE_CLAUDE_ENV_TOKEN=1 FAKE_TOKEN_MODE=fail
out=$(claude_access_token 2>"$FAKE_DIR/stderr") || fail '钥匙串续期失败时应借用桌面版 token'
assert_eq "$out" fake-env-12345 '应借用最新启动的桌面版进程的 token'
assert_eq "$(count "$FAKE_DIR/token_calls")" 1 '应先尝试续期钥匙串一次'

reset_case desktop_no_keychain
export FAKE_CLAUDE_RUNNING=1 FAKE_CLAUDE_ENV_TOKEN=1
out=$(claude_access_token 2>"$FAKE_DIR/stderr") || fail '钥匙串没有凭证时也应借用桌面版 token'
assert_eq "$out" fake-env-12345 '无钥匙串凭证时桌面版 token 输出错误'

reset_case desktop_force
credentials_json fake-old-access fake-old-refresh "$EXPIRED" "$REFRESH_FRESH" >"$FAKE_DIR/credentials"
export FAKE_CLAUDE_RUNNING=1 FAKE_CLAUDE_ENV_TOKEN=1
out=$(claude_access_token force 2>"$FAKE_DIR/stderr") || fail '桌面版 token 401 后应续期钥匙串'
assert_eq "$out" fake-new-access '桌面版内嵌进程运行时续期后 access token 错误'
assert_eq "$(count "$FAKE_DIR/token_calls")" 1 '桌面版内嵌进程运行时应只续期一次'

reset_case keychain_first
credentials_json fake-old-access fake-old-refresh "$FRESH" "$REFRESH_FRESH" >"$FAKE_DIR/credentials"
export FAKE_CLAUDE_RUNNING=1 FAKE_CLAUDE_ENV_TOKEN=1
out=$(claude_access_token 2>"$FAKE_DIR/stderr") || fail '钥匙串 token 未过期时应可读取'
assert_eq "$out" fake-old-access '钥匙串 token 未过期时应优先于桌面版 token'

reset_case refresh
credentials_json fake-old-access fake-old-refresh "$EXPIRED" "$REFRESH_FRESH" >"$FAKE_DIR/credentials"
out=$(claude_access_token 2>"$FAKE_DIR/stderr") || fail '过期 token 应成功续期'
assert_eq "$out" fake-new-access '续期后 access token 错误'
assert_eq "$(count "$FAKE_DIR/token_calls")" 1 '应只续期一次'
grep -qxF "$CLAUDE_USER_AGENT" "$FAKE_DIR/curl_argv" || fail '续期请求应带面板专属 User-Agent（常见 UA 会被 429）'
assert_eq "$(cat "$FAKE_DIR/written_account")" test-account '写回时应保留钥匙串 account'
if grep -q 'fake-old-refresh' "$FAKE_DIR/curl_argv"; then
  fail 'curl 命令行参数不应包含 refresh token'
fi
grep -q 'fake-old-refresh' "$FAKE_DIR/curl_stdin" || fail 'curl 应从标准输入读取 refresh token'
jq -e '
  .topLevel == "keep" and .claudeAiOauth.keptField.nested == true
  and .claudeAiOauth.rateLimitTier == "tier-test"
  and .claudeAiOauth.subscriptionType == "pro"
  and .claudeAiOauth.accessToken == "fake-new-access"
  and .claudeAiOauth.refreshToken == "fake-new-refresh"
  and (.claudeAiOauth.refreshTokenExpiresAt > .claudeAiOauth.expiresAt)
' "$FAKE_DIR/written_json" >/dev/null || fail '写回 JSON 未正确保留或更新字段'

reset_case reread
credentials_json fake-old-access fake-old-refresh "$EXPIRED" "$REFRESH_FRESH" >"$FAKE_DIR/credentials"
credentials_json fake-other-access fake-other-refresh "$FRESH" "$REFRESH_FRESH" >"$FAKE_DIR/credentials_second"
out=$(claude_access_token 2>"$FAKE_DIR/stderr") || fail '上锁后应采用别人续期的新 token'
assert_eq "$out" fake-other-access '重读后输出错误'
assert_eq "$(count "$FAKE_DIR/token_calls")" 0 '重读发现已续期时不应重复续期'

reset_case backoff
credentials_json fake-old-access fake-old-refresh "$EXPIRED" "$REFRESH_FRESH" >"$FAKE_DIR/credentials"
export FAKE_TOKEN_MODE=fail
if claude_access_token >"$FAKE_DIR/stdout1" 2>"$FAKE_DIR/stderr1"; then
  fail 'OAuth 失败时应返回失败'
fi
[ -f "$HOME/.cache/sketchybar/claude_token_refresh.fail" ] || fail 'OAuth 失败应写退避标记'
if claude_access_token >"$FAKE_DIR/stdout2" 2>"$FAKE_DIR/stderr2"; then
  fail '退避期内应返回失败'
fi
assert_eq "$(count "$FAKE_DIR/token_calls")" 1 '退避期内不应再次请求 OAuth'

reset_case refresh_expired
credentials_json fake-old-access fake-old-refresh "$EXPIRED" "$REFRESH_EXPIRED" >"$FAKE_DIR/credentials"
if claude_access_token >"$FAKE_DIR/stdout" 2>"$FAKE_DIR/stderr"; then
  fail 'refresh token 过期时应返回失败'
fi
assert_eq "$(count "$FAKE_DIR/token_calls")" 0 'refresh token 过期时不应续期'

reset_case missing_access
credentials_json fake-old-access fake-old-refresh "$EXPIRED" "$REFRESH_FRESH" >"$FAKE_DIR/credentials"
export FAKE_TOKEN_MODE=missing_access
if claude_access_token >"$FAKE_DIR/stdout" 2>"$FAKE_DIR/stderr"; then
  fail '响应缺 access token 时应返回失败'
fi
[ ! -f "$FAKE_DIR/written_json" ] || fail '响应缺 access token 时不应写回钥匙串'

reset_case no_refresh_expiry
credentials_json fake-old-access fake-old-refresh "$EXPIRED" "$REFRESH_FRESH" >"$FAKE_DIR/credentials"
export FAKE_TOKEN_MODE=no_refresh_expiry
out=$(claude_access_token 2>"$FAKE_DIR/stderr") || fail '响应缺 refresh token 过期字段时仍应成功续期'
assert_eq "$out" fake-new-access '缺 refresh token 过期字段时 access token 输出错误'
jq -e --argjson original_expiry "$REFRESH_FRESH" '
  .claudeAiOauth.accessToken == "fake-new-access"
  and .claudeAiOauth.refreshToken == "fake-new-refresh"
  and .claudeAiOauth.refreshTokenExpiresAt == $original_expiry
' "$FAKE_DIR/written_json" >/dev/null || fail '响应缺 refresh token 过期字段时应保留原到期时间'

reset_case usage_401
credentials_json fake-old-access fake-old-refresh "$FRESH" "$REFRESH_FRESH" >"$FAKE_DIR/credentials"
mkdir -p "$HOME/.config/scripts/lib"
cat >"$HOME/.config/scripts/lib/common.sh" <<EOF
SCRIPTS_DIR="$ROOT/scripts"
color_alpha() { printf '%s\n' "\$1"; }
COLOR_BG=bg
COLOR_SURFACE=surface
COLOR_ACCENT=green
COLOR_WARNING=orange
COLOR_DANGER=red
COLOR_SURFACE_ALT=track
COLOR_BORDER=grey
COLOR_SUBTEXT=subtext
USAGE_RESET_WIDTH=0
EOF
export FAKE_USAGE_401_FIRST=1 NAME=claude_usage
bash "$ROOT/scripts/sketchybar/ai_usage.sh" >"$FAKE_DIR/stdout" 2>"$FAKE_DIR/stderr" || fail '用量接口 401 后重试应成功'
assert_eq "$(count "$FAKE_DIR/usage_calls")" 2 '用量接口 401 后应只重试一次'
grep -qxF "$CLAUDE_USER_AGENT" "$FAKE_DIR/curl_argv" || fail '用量请求应带面板专属 User-Agent'
assert_eq "$(count "$FAKE_DIR/token_calls")" 1 '用量接口 401 后应只续期一次'

# 面板后台任务 ai_fetch：成功写缓存、429 按 Retry-After 退避、登录到期报“需登录”。
run_ai_fetch() {
  mkdir -p "$FAKE_DIR/panel/bin"
  printf '#!/bin/bash\nexit 0\n' >"$FAKE_DIR/panel/bin/panel"
  chmod +x "$FAKE_DIR/panel/bin/panel"
  PANEL_DIR="$FAKE_DIR/panel" PANEL_USAGE_CACHE="$FAKE_DIR/usage" \
    PANEL_CLAUDE_TOKEN_HELPER="$ROOT/scripts/sketchybar/claude_token.sh" \
    bash "$ROOT/panel/jobs/ai_fetch" >"$FAKE_DIR/stdout" 2>>"$FAKE_DIR/stderr" || true
}

reset_case fetch_ok
credentials_json fake-old-access fake-old-refresh "$FRESH" "$REFRESH_FRESH" >"$FAKE_DIR/credentials"
run_ai_fetch
jq -e '.seven_day.utilization == 20' "$FAKE_DIR/usage/claude.json" >/dev/null || fail 'ai_fetch 成功时应写入用量缓存'
[ ! -f "$FAKE_DIR/usage/claude.error" ] || fail 'ai_fetch 成功时应清除错误标记'
grep -qxF "$CLAUDE_USER_AGENT" "$FAKE_DIR/curl_argv" || fail 'ai_fetch 用量请求应带面板专属 User-Agent'
assert_eq "$(cat "$FAKE_DIR/usage/claude.login_expires")" "$((REFRESH_FRESH / 1000))" 'ai_fetch 应记录登录到期时间'

reset_case fetch_429
credentials_json fake-old-access fake-old-refresh "$FRESH" "$REFRESH_FRESH" >"$FAKE_DIR/credentials"
export FAKE_USAGE_429=1 FAKE_RETRY_AFTER=600
before=$(date +%s)
run_ai_fetch
assert_eq "$(cat "$FAKE_DIR/usage/claude.error")" 限流 '429 时应标记限流'
until_epoch=$(cat "$FAKE_DIR/usage/claude.retry_until")
[ "$until_epoch" -ge "$((before + 600))" ] && [ "$until_epoch" -le "$(($(date +%s) + 600))" ] ||
  fail '429 时应按 Retry-After 记录下次请求时间'
grep -q 'HTTP 429，600 秒后再试' "$FAKE_DIR/stderr" || fail '429 时日志应写明原因'
rm -f "$FAKE_DIR/usage/claude.fail"
run_ai_fetch
assert_eq "$(count "$FAKE_DIR/usage_calls")" 1 'Retry-After 期间不应再次请求用量接口'

reset_case fetch_429_no_header
credentials_json fake-old-access fake-old-refresh "$FRESH" "$REFRESH_FRESH" >"$FAKE_DIR/credentials"
export FAKE_USAGE_429=1
before=$(date +%s)
run_ai_fetch
[ "$(cat "$FAKE_DIR/usage/claude.retry_until")" -ge "$((before + 900))" ] || fail '没有 Retry-After 时应默认退避 900 秒'

reset_case fetch_login_expired
credentials_json fake-old-access fake-old-refresh "$EXPIRED" "$REFRESH_EXPIRED" >"$FAKE_DIR/credentials"
run_ai_fetch
assert_eq "$(cat "$FAKE_DIR/usage/claude.error")" 需登录 '登录到期时应标记需登录'
grep -q '登录已过期' "$FAKE_DIR/stderr" || fail '登录到期时日志应写明原因'
assert_eq "$(count "$FAKE_DIR/token_calls")" 0 '登录到期时不应请求续期'

if find "$TEST_TMP" -name 'stderr*' -type f -exec grep -E 'fake-(old|new|other)-(access|refresh)' {} + >/dev/null 2>&1; then
  fail 'stderr 泄露了 token'
fi

printf '%s\n' 'Claude token 续期测试通过。'
