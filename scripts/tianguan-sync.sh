#!/usr/bin/env bash
# /opt/oddjobs/jobs/tianguan-sync.sh —— 上游有新 commit 时：①同步 fork ②触发打包流水线
#
# 由 /opt/oddjobs/run-job.sh 调用（负责 flock + 日志 + 退出码）。
#
# 逻辑：
#   1. 取上游最新 commit sha（api.github.com 优先，atom feed 兜底）
#   2. 若与「已同步 sha」不同 → merge-upstream（幂等；200 即表示已是最新）
#   3. 若与「已触发打包的 sha」不同 → POST repository_dispatch 到打包仓库（payload 带 sha）
#   两个 sha 分开记账 ⇒ dispatch 失败时下一轮会自动重试，不会漏、也不会重复
#
# 手工用法：
#   run-job.sh tianguan-sync                 # 正常
#   jobs/tianguan-sync.sh --check            # 只看状态
#   jobs/tianguan-sync.sh --force            # 忽略记录，强制 merge + dispatch
#
# 退出码：0 正常；1 失败；2 缺 token

set -uo pipefail

# ---------------- 配置 ----------------
# 三个仓库名都可用环境变量覆盖，方便别人复刻这套自动同步：
#   UPSTREAM=上游上游/仓库 FORK=你的/fork PACK_REPO=你的/打包仓库 ./tianguan-sync.sh
UPSTREAM="${UPSTREAM:-TianguanStation/Tianguan13}"
FORK="${FORK:-rrrrrede1/Tianguan13}"
BRANCH="${BRANCH:-main}"
# 打包仓库（空 = 不触发打包）。留空也能跑，只是不派发。
PACK_REPO="${PACK_REPO:-rrrrrede1/tianguan13-server-pack}"
PACK_EVENT="${PACK_EVENT:-source-updated}"

TOKEN_FILE="${TOKEN_FILE:-/root/.config/tianguan-sync/token}"
STATE_DIR="${STATE_DIR:-/root/.local/state/tianguan-sync}"
MERGED_SHA_FILE="$STATE_DIR/last-upstream-sha"
DISPATCHED_SHA_FILE="$STATE_DIR/last-dispatched-sha"

MODE="sync"
case "${1:-}" in
  --check) MODE="check" ;;
  --force) MODE="force" ;;
  "") ;;
  *) echo "unknown arg: $1" >&2; exit 64 ;;
esac

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*"; }

token=""
[ -s "$TOKEN_FILE" ] && token=$(tr -d '\r\n' <"$TOKEN_FILE")

api_sha() { # $1=owner/repo
  local out code sha
  if [ -n "$token" ]; then
    out=$(curl -sS --max-time 25 -w '\n%{http_code}' \
      -H "Authorization: Bearer $token" -H 'Accept: application/vnd.github.sha' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      "https://api.github.com/repos/$1/commits/$BRANCH" 2>/dev/null)
  else
    out=$(curl -sS --max-time 25 -w '\n%{http_code}' -H 'Accept: application/vnd.github.sha' \
      "https://api.github.com/repos/$1/commits/$BRANCH" 2>/dev/null)
  fi
  code=$(printf '%s' "$out" | tail -n1)
  sha=$(printf '%s' "$out" | head -n1 | tr -d '\r')
  [ "$code" = "200" ] || { echo "api_sha($1) http=$code" >&2; return 1; }
  case "$sha" in *[!0-9a-f]*) echo "api_sha($1) not a sha" >&2; return 1 ;; esac
  [ ${#sha} -eq 40 ] || { echo "api_sha($1) bad length" >&2; return 1; }
  printf '%s' "$sha"
}

atom_sha() { # $1=owner/repo
  local body
  body=$(curl -fsS --max-time 25 -H 'Accept: application/atom+xml' \
    "https://github.com/$1/commits/$BRANCH.atom" 2>/dev/null) || return 1
  printf '%s' "$body" | grep -o 'Grit::Commit/[0-9a-f]\{40\}' | head -n1 | cut -d/ -f2
}

head_sha() { # $1=owner/repo
  local s
  if s=$(api_sha "$1") && [ -n "$s" ]; then printf '%s' "$s"; return 0; fi
  log "WARN api 取 sha 失败，退回 atom feed（$1）"
  atom_sha "$1"
}

read_state() { [ -f "$1" ] && tr -d '\r\n' <"$1" || true; }
write_state() { mkdir -p "$STATE_DIR"; printf '%s\n' "$2" >"$1"; }

# ---------------- 取上游 ----------------
if ! up=$(head_sha "$UPSTREAM") || [ -z "${up:-}" ]; then
  log "ERROR 取不到上游 sha"
  exit 1
fi
merged=$(read_state "$MERGED_SHA_FILE")
dispatched=$(read_state "$DISPATCHED_SHA_FILE")

if [ "$MODE" = "check" ]; then
  log "check: upstream=${up:0:7} merged=${merged:0:7} dispatched=${dispatched:0:7} pack_repo=${PACK_REPO:-<未配置>}"
  exit 0
fi

# 都跟上了就早退（两个 sha 都等于上游才算完）
if [ "$MODE" != "force" ] && [ "$merged" = "$up" ] && { [ -z "$PACK_REPO" ] || [ "$dispatched" = "$up" ]; }; then
  log "上游无新 commit（${up:0:7}），无需动作"
  exit 0
fi

# ---------------- ① 同步 fork ----------------
if [ "$MODE" = "force" ] || [ "$merged" != "$up" ]; then
  if [ -z "$token" ]; then log "ERROR 缺少 token：$TOKEN_FILE"; exit 2; fi
  body=$(mktemp); trap 'rm -f "$body"' EXIT
  code=$(curl -sS --max-time 60 -o "$body" -w '%{http_code}' \
    -X POST -H "Authorization: Bearer $token" -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' -d "{\"branch\":\"$BRANCH\"}" \
    "https://api.github.com/repos/$FORK/merge-upstream" 2>/dev/null) || code="000"
  msg=$(grep -o '"message": *"[^"]*"' "$body" 2>/dev/null | head -n1 | sed 's/.*: *"//; s/"$//')
  mtype=$(grep -o '"merge_type": *"[^"]*"' "$body" 2>/dev/null | head -n1 | sed 's/.*: *"//; s/"$//')
  log "merge-upstream HTTP $code merge_type=${mtype:-?} msg=${msg:-无}"

  case "$code" in
    200) write_state "$MERGED_SHA_FILE" "$up"; log "fork 已同步 ${up:0:7}" ;;
    409) log "ERROR 冲突：上游改动与本 fork 改动重叠，需手动解决一次（本次不记账，下轮重试）"; exit 1 ;;
    401) log "ERROR token 无效（401）"; exit 1 ;;
    403|422) log "ERROR 被拒（$code）：token 权限不足或上游改了 .github/workflows/**"; exit 1 ;;
    *) log "ERROR 未预期响应（$code）"; exit 1 ;;
  esac
fi

# ---------------- ② 触发打包 ----------------
if [ -z "$PACK_REPO" ]; then
  log "PACK_REPO 未配置，跳过打包触发"
  exit 0
fi

if [ "$MODE" != "force" ] && [ "$dispatched" = "$up" ]; then
  log "打包已触发过（${up:0:7}），跳过"
  exit 0
fi

if [ -z "$token" ]; then log "ERROR 缺少 token（dispatch 也需要）"; exit 2; fi

resp=$(mktemp)
dcode=$(curl -sS --max-time 40 -o "$resp" -w '%{http_code}' \
  -X POST -H "Authorization: Bearer $token" -H 'Accept: application/vnd.github+json' \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -d "{\"event_type\":\"$PACK_EVENT\",\"client_payload\":{\"sha\":\"$up\",\"source_repo\":\"$FORK\"}}" \
  "https://api.github.com/repos/$PACK_REPO/dispatches" 2>/dev/null) || dcode="000"
if [ "$dcode" = "204" ] || [ "$dcode" = "200" ]; then
  write_state "$DISPATCHED_SHA_FILE" "$up"
  log "已触发打包：$PACK_REPO (event=$PACK_EVENT sha=${up:0:7}) HTTP $dcode"
else
  log "WARN 触发打包失败 HTTP $dcode：$(head -c 200 "$resp" 2>/dev/null | tr -d '\n')"
  log "WARN 不记账，下一轮会自动重试"
fi
rm -f "$resp"
exit 0
