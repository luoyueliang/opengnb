#!/usr/bin/env bash
# Interactive release flow:
# 1) 运行 scripts/sync_source.sh（交互式），同步 src 并创建本地源码标签
# 2) 根据源码标签/版本文件生成发布标签（v*.*.*），可修改
# 3) 创建/移动发布标签到当前提交
# 4) 询问是否发布（推送标签以触发 CI）
#
# 本脚本为全交互式，不接受任何参数。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SUBDIR="."
RELEASE_TAG=""

usage() {
  echo "Usage: $0 (interactive only, no arguments accepted)" 1>&2
  exit 1
}

is_tty() { [ -t 0 ] && [ -t 1 ]; }

prompt() {
  local msg="$1"; shift
  local def="${1:-}"
  local val
  if [[ -n "$def" ]]; then
    read -r -p "$msg [$def]: " val || true
    echo "${val:-$def}"
  else
    read -r -p "$msg: " val || true
    echo "$val"
  fi
}

confirm() {
  local msg="$1"; shift
  local ans
  read -r -p "$msg [y/N]: " ans || true
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}
[[ $# -eq 0 ]] || usage

# 1) 源码同步（按需）：存在历史与 src/ 时允许跳过，否则执行同步
echo "== Step 1/3: Source sync (conditional) =="
HIST_FILE="${ROOT_DIR}/sources/history.ndjson"
HAS_HISTORY=0; LAST_SUMMARY=""
if [[ -s "$HIST_FILE" ]]; then
  HAS_HISTORY=1
  last_line=$(tail -n 1 "$HIST_FILE" || true)
  if [[ "$last_line" =~ \"source\"\:\{.*\"ref\"\:\"([^\"]+)\".*\} ]]; then src_ref="${BASH_REMATCH[1]}"; else src_ref="?"; fi
  if [[ "$last_line" =~ \"local\"\:\{.*\"tag\"\:\"([^\"]+)\".*\} ]]; then src_tag="${BASH_REMATCH[1]}"; else src_tag="?"; fi
  if [[ "$last_line" =~ \"timestamp\"\:\"([^\"]+)\" ]]; then ts="${BASH_REMATCH[1]}"; else ts="?"; fi
  LAST_SUMMARY="last_tag=${src_tag}, source_ref=${src_ref}, at ${ts}"
fi

if [[ -d "${ROOT_DIR}/src" && $HAS_HISTORY -eq 1 ]]; then
  echo "Detected existing src/ and history ($LAST_SUMMARY)"
  ans=$(prompt "Skip source sync and reuse current src?" "y")
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    echo "Skip syncing source."
  else
    echo "Running sync_source.sh ..."
    bash "${ROOT_DIR}/scripts/sync_source.sh" --subdir "$SUBDIR" || true
  fi
else
  echo "No existing src or history; running sync_source.sh ..."
  bash "${ROOT_DIR}/scripts/sync_source.sh" --subdir "$SUBDIR" || true
fi

# 2) Determine the local source tag from history or fallback to user input
echo "== Step 2/3: Determining local source tag =="
LOCAL_SRC_TAG=""
if [[ -f "$HIST_FILE" ]]; then
  last_line=$(tail -n 1 "$HIST_FILE" || true)
  # naive JSON extract: find \"tag\":\"...\"
  if [[ "$last_line" =~ \"tag\"\:\"([^\"]+)\" ]]; then
    LOCAL_SRC_TAG="${BASH_REMATCH[1]}"
  fi
fi

if [[ -z "$LOCAL_SRC_TAG" ]]; then
  echo "Couldn't infer local source tag from history; please enter it."
  LOCAL_SRC_TAG=$(prompt "Local source tag just created by sync_source.sh")
fi

if [[ -z "$LOCAL_SRC_TAG" ]]; then
  echo "Local source tag is required." 1>&2
  exit 2
fi

# Preflight: commit local changes (e.g., workflow updates) before creating tag
echo "== Preflight: Commit local changes (optional) =="
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Detected local changes:" 
  git --no-pager status --porcelain
  if confirm "Commit these changes now so the release tag includes them?"; then
    default_msg="chore(release): preflight updates"
    msg=$(prompt "Commit message" "$default_msg")
    git add -A
    git commit -m "$msg" || true
  else
    echo "Proceeding without committing local changes."
  fi
else
  echo "No local changes to commit."
fi

# 3) Decide a release tag (v*.*.*) and create/move it to current HEAD
echo "== Step 3/3: Creating/pushing release tag to trigger CI =="

propose_release_tag() {
  local from_src_tag="$1"
  local ver_file="${ROOT_DIR}/src/version"
  local candidate=""
  if [[ "$from_src_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    candidate="$from_src_tag"
  elif [[ -f "$ver_file" ]]; then
    local v
    v=$(head -n1 "$ver_file" | tr -d '\r' | xargs || true)
    if [[ -n "$v" ]]; then
      if [[ "$v" =~ ^v ]]; then candidate="$v"; else candidate="v${v}"; fi
    fi
  fi
  if [[ -z "$candidate" ]]; then
    # fallback: prefix v to src tag
    if [[ "$from_src_tag" =~ ^v ]]; then candidate="$from_src_tag"; else candidate="v${from_src_tag}"; fi
  fi
  echo "$candidate"
}

DEFAULT_REL_TAG=$(propose_release_tag "$LOCAL_SRC_TAG")
RELEASE_TAG=$(prompt "Release tag to create (must match v*.*.* to trigger CI)" "$DEFAULT_REL_TAG")

if [[ -z "$RELEASE_TAG" ]]; then
  echo "Release tag is required." 1>&2
  exit 3
fi

if [[ ! "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(\..*)?$ ]]; then
  echo "Warning: '$RELEASE_TAG' does not match pattern v*.*.*; build_linux.yml may not trigger on push." 1>&2
  if ! confirm "Continue anyway?"; then exit 4; fi
fi

CURRENT_HEAD=$(git rev-parse --short=12 HEAD)
MOVED_TAG=0

if git rev-parse -q --verify "refs/tags/$RELEASE_TAG" >/dev/null; then
  echo "Tag '$RELEASE_TAG' already exists."
  if confirm "Move tag '$RELEASE_TAG' to HEAD ($CURRENT_HEAD)?"; then
    git tag -fa "$RELEASE_TAG" -m "Release $RELEASE_TAG (src:$LOCAL_SRC_TAG)" HEAD
    MOVED_TAG=1
  else
    echo "Leaving tag as-is."
  fi
else
  git tag -a "$RELEASE_TAG" -m "Release $RELEASE_TAG (src:$LOCAL_SRC_TAG)" HEAD
fi

echo "Created/updated tag '$RELEASE_TAG' -> $(git rev-parse --short=12 "$RELEASE_TAG^{commit}")"

# Ask to publish (push tag)
echo
if confirm "Publish now (push tag to remote to trigger CI)?"; then
  # Determine remote
  REMOTE="origin"
  if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
    REMOTES=()
    while IFS= read -r _r; do [[ -n "$_r" ]] && REMOTES+=("$_r"); done < <(git remote)
    if [[ ${#REMOTES[@]} -eq 0 ]]; then
      echo "No git remotes configured" 1>&2
      exit 2
    fi
    echo "Select a remote to push:"
    for i in "${!REMOTES[@]}"; do echo "  $((i+1))) ${REMOTES[$i]}"; done
    read -r -p "Enter choice [1-${#REMOTES[@]}]: " rsel || true
    if [[ "$rsel" =~ ^[0-9]+$ ]] && (( rsel >=1 && rsel <= ${#REMOTES[@]} )); then
      REMOTE="${REMOTES[$((rsel-1))]}"
    else
      echo "Invalid choice" 1>&2; exit 2
    fi
  fi

  echo "Pushing tag '$RELEASE_TAG' to $REMOTE ..."
  # First push current branch so remote has the commit on the branch as well
  CUR_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)
  if [[ "$CUR_BRANCH" != "HEAD" ]]; then
    echo "Pushing current branch '$CUR_BRANCH' to $REMOTE ..."
    if git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
      git push "$REMOTE" "$CUR_BRANCH"
    else
      git push -u "$REMOTE" "$CUR_BRANCH"
    fi
  else
    echo "Detached HEAD; no branch push."
  fi

  git push -f "$REMOTE" "$RELEASE_TAG"
  echo "Done. GitHub Actions should trigger for '$RELEASE_TAG' (see .github/workflows/build_linux.yml)."
else
  echo "Tag created locally. You can publish later with: git push origin $RELEASE_TAG"
fi

exit 0
