#!/usr/bin/env bash
#
# count.sh — 列出 $GH_USER 所有非 fork repo → 淺 clone → tokei → 累積到 data/history.json
#
# 環境變數：
#   GH_USER     必填  GitHub username (預設 MAXXTANG)
#   GH_TOKEN    建議  GitHub PAT 或 GITHUB_TOKEN，沒給用 gh auth
#   INCLUDE_PRIVATE  選用  1=包含私有 repo（需要 PAT 有 repo scope）
#   OUT_FILE    選用  輸出檔（預設 data/history.json）
#
# 依賴：gh / tokei / jq / git

set -euo pipefail

GH_USER="${GH_USER:-MAXXTANG}"
INCLUDE_PRIVATE="${INCLUDE_PRIVATE:-0}"
OUT_FILE="${OUT_FILE:-data/history.json}"
TMP_DIR="$(mktemp -d -t maxxtang-loc-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ──────────────────────────────────────────────────────────────────────────
# 0. 依賴檢查
# ──────────────────────────────────────────────────────────────────────────
for cmd in gh tokei jq git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ 缺少依賴: $cmd" >&2
    exit 1
  fi
done

# ──────────────────────────────────────────────────────────────────────────
# 1. 列 repo（排除 fork、排除 archived）
# ──────────────────────────────────────────────────────────────────────────
echo "📋 列出 $GH_USER 的 repo..."

VISIBILITY_FLAG="--visibility public"
if [[ "$INCLUDE_PRIVATE" == "1" ]]; then
  VISIBILITY_FLAG=""
fi

# gh repo list 在被認證用戶等於 GH_USER 時可以列私有；否則只能列公開
REPO_JSON="$TMP_DIR/repos.json"
gh repo list "$GH_USER" \
  --limit 1000 \
  $VISIBILITY_FLAG \
  --no-archived \
  --source \
  --json name,nameWithOwner,defaultBranchRef,isFork,diskUsage,primaryLanguage \
  > "$REPO_JSON"

REPO_COUNT=$(jq 'length' "$REPO_JSON")
echo "   找到 $REPO_COUNT 個 repo（已排除 fork / archived）"

# ──────────────────────────────────────────────────────────────────────────
# 2. 對每個 repo 淺 clone → tokei
# ──────────────────────────────────────────────────────────────────────────
AGG_FILE="$TMP_DIR/aggregate.json"
echo '{"by_repo":{},"by_language":{},"total_lines":0,"total_code":0,"total_comments":0,"total_blanks":0}' > "$AGG_FILE"

i=0
while IFS= read -r repo; do
  i=$((i+1))
  name=$(jq -r '.name' <<<"$repo")
  branch=$(jq -r '.defaultBranchRef.name // "main"' <<<"$repo")
  echo "  [$i/$REPO_COUNT] $name (branch: $branch)"

  repo_dir="$TMP_DIR/repos/$name"
  if ! git clone --depth=1 --branch "$branch" --quiet \
       "https://github.com/$GH_USER/$name.git" "$repo_dir" 2>/dev/null; then
    echo "     ⚠️  clone 失敗（可能是空 repo），跳過"
    continue
  fi

  # tokei 輸出 JSON
  tokei_json="$TMP_DIR/tokei-$name.json"
  if ! tokei --output json "$repo_dir" > "$tokei_json" 2>/dev/null; then
    echo "     ⚠️  tokei 失敗，跳過"
    continue
  fi

  # 把這個 repo 的數字合進 aggregate
  jq --slurpfile t "$tokei_json" --arg name "$name" '
    . as $agg |
    ($t[0] // {}) as $tk |
    # tokei JSON 結構：{ "Rust": {...}, "Python": {...}, "Total": {...} }
    # ⚠️ 必須過濾掉 "Total" 否則會雙倍計算
    reduce ($tk | to_entries | map(select(.key != "Total")) | .[]) as $lang (
      $agg;
      .by_repo[$name] = (.by_repo[$name] // {code:0,comments:0,blanks:0}) |
      .by_repo[$name].code     += ($lang.value.code // 0) |
      .by_repo[$name].comments += ($lang.value.comments // 0) |
      .by_repo[$name].blanks   += ($lang.value.blanks // 0) |
      .by_language[$lang.key] = (.by_language[$lang.key] // {code:0,comments:0,blanks:0}) |
      .by_language[$lang.key].code     += ($lang.value.code // 0) |
      .by_language[$lang.key].comments += ($lang.value.comments // 0) |
      .by_language[$lang.key].blanks   += ($lang.value.blanks // 0) |
      .total_code     += ($lang.value.code // 0) |
      .total_comments += ($lang.value.comments // 0) |
      .total_blanks   += ($lang.value.blanks // 0)
    ) |
    .total_lines = (.total_code + .total_comments + .total_blanks)
  ' "$AGG_FILE" > "$AGG_FILE.tmp" && mv "$AGG_FILE.tmp" "$AGG_FILE"
done < <(jq -c '.[]' "$REPO_JSON")

# ──────────────────────────────────────────────────────────────────────────
# 3. 組裝這次快照
# ──────────────────────────────────────────────────────────────────────────
TODAY=$(date -u +%Y-%m-%d)
SNAPSHOT=$(jq --arg date "$TODAY" --arg user "$GH_USER" --argjson n "$REPO_COUNT" '
  {
    date: $date,
    user: $user,
    repo_count: $n,
    total_lines: .total_lines,
    total_code: .total_code,
    total_comments: .total_comments,
    total_blanks: .total_blanks,
    by_language: .by_language,
    by_repo: .by_repo
  }
' "$AGG_FILE")

# ──────────────────────────────────────────────────────────────────────────
# 4. 寫進 history.json（同一天的覆蓋，不同天 append）
# ──────────────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$OUT_FILE")"
if [[ ! -f "$OUT_FILE" ]]; then
  echo '{"user":"'"$GH_USER"'","snapshots":[]}' > "$OUT_FILE"
fi

jq --argjson snap "$SNAPSHOT" --arg date "$TODAY" '
  .snapshots = (
    (.snapshots // []) |
    map(select(.date != $date)) + [$snap]
  ) |
  .snapshots |= sort_by(.date) |
  .updated_at = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
' "$OUT_FILE" > "$OUT_FILE.tmp" && mv "$OUT_FILE.tmp" "$OUT_FILE"

# ──────────────────────────────────────────────────────────────────────────
# 5. 顯示總結
# ──────────────────────────────────────────────────────────────────────────
TOTAL=$(jq '.total_lines' <<<"$SNAPSHOT")
CODE=$(jq '.total_code' <<<"$SNAPSHOT")
echo ""
echo "✅ 快照完成 ($TODAY)"
echo "   Repos:       $REPO_COUNT"
echo "   Total lines: $TOTAL"
echo "   Code lines:  $CODE"
echo "   寫入: $OUT_FILE"
