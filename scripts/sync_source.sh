#!/usr/bin/env bash
set -euo pipefail

# Sync external source repo into local ./src, commit, tag, and record mapping.
#
# Usage:
#   scripts/sync_source.sh [--subdir path/in/repo] [--push] [--push-remote origin] [--push-branch <branch>] [--yes]
#
# Notes:
# - Creates/updates ./src with contents from the external repo (subdir if provided).
# - Commits the change with a message referencing source repo/ref/sha.
# - Creates a local tag: src-sync/<version|ref> (with timestamp suffix if exists).
# - Appends a JSON line to sources/history.ndjson for traceability.

usage() {
  echo "Usage: $0 [--subdir <path>] [--push] [--push-remote origin] [--push-branch <branch>] [--yes]" 1>&2
  echo "       Interactive wizard will list source tags from gnbdev/opengnb and target tags in this repo." 1>&2
  exit 1
}

REPO="gnbdev/opengnb"; REF=""; SUBDIR="."; VERSION=""; ASSUME_YES=0; PUSH=0; PUSH_REMOTE="origin"; PUSH_BRANCH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subdir) SUBDIR="$2"; shift 2 ;;
    --push) PUSH=1; shift ;;
    --push-remote) PUSH_REMOTE="$2"; shift 2 ;;
    --push-branch) PUSH_BRANCH="$2"; shift 2 ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

is_tty() { [ -t 0 ] && [ -t 1 ]; }

prompt() {
  local msg="$1"; shift
  local def="${1:-}"
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
  local expect_yes=${1:-n}
  if [[ $ASSUME_YES -eq 1 ]]; then return 0; fi
  local ans
  if [[ "$expect_yes" == "strict" ]]; then
    read -r -p "$msg Type YES to continue: " ans || true
    [[ "$ans" == "YES" ]]
  else
    read -r -p "$msg [y/N]: " ans || true
    [[ "$ans" == "y" || "$ans" == "Y" ]]
  fi
}

has_sort_V() { sort -V </dev/null >/dev/null 2>&1; }

list_remote_tags() {
  local repo="$1"
  git ls-remote --tags --refs "https://github.com/${repo}.git" 2>/dev/null | awk '{print $2}' | sed 's#refs/tags/##'
}

list_local_tags() {
  if has_sort_V; then
    git tag --list | sort -V || true
  else
    git tag --list | sort || true
  fi
}

# Interactive wizard if needed
if is_tty; then
  echo "== gnb source sync wizard (fixed source: $REPO) =="
  # 1) Select source tag from remote list (with Latest shortcut)
  echo "Fetching tags from $REPO ..."
  # Build REMOTE_TAGS array without mapfile (for bash 3.2 compatibility)
  REMOTE_TAGS=()
  while IFS= read -r _line; do
    [[ -n "$_line" ]] && REMOTE_TAGS+=("$_line")
  done < <(list_remote_tags "$REPO")
  if [[ ${#REMOTE_TAGS[@]} -eq 0 ]]; then
    echo "No tags found in remote $REPO" 1>&2
    exit 1
  fi
  # Sort with -V when available
  if has_sort_V; then
    IFS=$'\n' REMOTE_TAGS=($(printf '%s\n' "${REMOTE_TAGS[@]}" | sort -V)); unset IFS
  else
    IFS=$'\n' REMOTE_TAGS=($(printf '%s\n' "${REMOTE_TAGS[@]}" | sort)); unset IFS
  fi
  _len=${#REMOTE_TAGS[@]}
  LATEST="${REMOTE_TAGS[$((_len - 1))]}"
  echo "Select source tag (0 for Latest: $LATEST):"
  echo "  0) Latest: $LATEST"
  for i in "${!REMOTE_TAGS[@]}"; do
    echo "  $((i+1))) ${REMOTE_TAGS[$i]}"
  done
  read -r -p "Enter choice [0-${#REMOTE_TAGS[@]}]: " choice || true
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 0 && choice <= ${#REMOTE_TAGS[@]} )); then
    if (( choice == 0 )); then REF="$LATEST"; else REF="${REMOTE_TAGS[$((choice-1))]}"; fi
  else
    echo "Invalid choice"; exit 1
  fi

  # 2) Select/compose target tag in this repo (offer same-as-source and time-based suggestion)
  echo "Scanning local tags ..."
  LOCAL_TAGS=()
  while IFS= read -r _l; do
    [[ -n "_l" ]] && LOCAL_TAGS+=("$_l")
  done < <(list_local_tags)
  SUGGEST1="$REF"
  SUGGEST2="${REF}-$(date +%Y%m%d)"
  echo "Choose target tag (release dir name)."
  echo "  1) $SUGGEST1 (same as source)"
  echo "  2) $SUGGEST2 (date suffixed)"
  echo "  3) Select existing local tag"
  read -r -p "Enter choice [1-3]: " tsel || true
  case "$tsel" in
    1) VERSION="$SUGGEST1" ;;
    2) VERSION="$SUGGEST2" ;;
    3)
      if [[ ${#LOCAL_TAGS[@]} -eq 0 ]]; then
        echo "No local tags exist; falling back to $SUGGEST1"
        VERSION="$SUGGEST1"
      else
        echo "Select a local tag:"
        for i in "${!LOCAL_TAGS[@]}"; do echo "  $((i+1))) ${LOCAL_TAGS[$i]}"; done
        read -r -p "Enter choice [1-${#LOCAL_TAGS[@]}]: " lch || true
        if [[ "$lch" =~ ^[0-9]+$ ]] && (( lch >= 1 && lch <= ${#LOCAL_TAGS[@]} )); then
          VERSION="${LOCAL_TAGS[$((lch-1))]}"
        else
          echo "Invalid choice"; exit 1
        fi
      fi
      ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac

  echo
  echo "Summary:"
  echo "  Source repo : $REPO"
  echo "  Source tag  : $REF"
  echo "  Source dir  : ${SUBDIR}"
  echo "  Target tag  : $VERSION"
  echo "  Destination : src/ (will be replaced, rsync --delete)"
  confirm "Proceed with sync?" || { echo "Aborted."; exit 1; }
  echo "This will OVERWRITE local src/ with remote content."
  confirm "Final confirmation." strict || { echo "Aborted."; exit 1; }
fi

[[ -n "$REF" && -n "$VERSION" ]] || { echo "Missing selections"; exit 1; }

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$ROOT_DIR/src"
HIST_DIR="$ROOT_DIR/sources"
HIST_FILE="$HIST_DIR/history.ndjson"

mkdir -p "$SRC_DIR" "$HIST_DIR"

# Ensure git identity
if ! git -C "$ROOT_DIR" config user.email >/dev/null; then
  git -C "$ROOT_DIR" config user.email "ci@local"
fi
if ! git -C "$ROOT_DIR" config user.name >/dev/null; then
  git -C "$ROOT_DIR" config user.name "gnb-sync"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Fetching $REPO @ $REF (subdir=$SUBDIR) ..."
(
  set -e
  cd "$WORK"
  git init src >/dev/null
  cd src
  git remote add origin "https://github.com/${REPO}.git"
  git -c advice.detachedHead=false fetch --depth 1 origin "$REF" >/dev/null
  git checkout --detach FETCH_HEAD >/dev/null
)
SRC_SHA=$(git -C "$WORK/src" rev-parse --short=12 HEAD)

echo "Syncing into $SRC_DIR ..."
rsync -a --delete --exclude '.git/' "$WORK/src/${SUBDIR%/}/" "$SRC_DIR/"

# Stage and commit
cd "$ROOT_DIR"
git add -A "$SRC_DIR"

DIFF_PREV=$(git rev-parse --short=12 HEAD 2>/dev/null || echo "")
if git diff --cached --quiet; then
  echo "No changes detected in src; nothing to commit."
  LOCAL_SHA=$(git rev-parse --short=12 HEAD)
else
  MSG="sync(src): ${REPO}@${REF} (${SRC_SHA}) -> src/"
  if [[ -n "$VERSION" ]]; then MSG+=" [version ${VERSION}]"; fi
  git commit -m "$MSG"
  LOCAL_SHA=$(git rev-parse --short=12 HEAD)
fi

# Tag
TAG_BASE="src-sync/"$( [[ -n "$VERSION" ]] && echo "$VERSION" || echo "$REF" )
TAG_NAME="$TAG_BASE"
if git rev-parse -q --verify "refs/tags/$TAG_NAME" >/dev/null; then
  TAG_NAME+="-$(date +%Y%m%d%H%M%S)"
fi
git tag "$TAG_NAME" -m "Source sync from ${REPO}@${REF} (${SRC_SHA})"

# Diffstat for record
DIFFSTAT=""
if [[ -n "$DIFF_PREV" ]]; then
  DIFFSTAT=$(git --no-pager diff --stat "$DIFF_PREV..HEAD" | tr '\n' ' ' | sed -E 's/\s+/ /g')
fi

# Record history (ndjson)
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat >> "$HIST_FILE" <<EOF
{"timestamp":"$TS","source":{"repo":"$REPO","ref":"$REF","commit":"$SRC_SHA","subdir":"$SUBDIR"},"local":{"commit":"$LOCAL_SHA","tag":"$TAG_NAME"},"paths":{"dest":"src"},"diffstat":"$DIFFSTAT"}
EOF

echo "Done. Local commit: $LOCAL_SHA, tag: $TAG_NAME"
echo "History appended to: $HIST_FILE"

# Optional push
if [[ $PUSH -eq 1 ]]; then
  # Determine branch
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD || echo HEAD)
  if [[ -z "$PUSH_BRANCH" ]]; then
    PUSH_BRANCH="$CURRENT_BRANCH"
  fi
  if [[ "$PUSH_BRANCH" == "HEAD" || -z "$PUSH_BRANCH" ]]; then
    echo "Cannot determine current branch (detached HEAD). Use --push-branch <branch>." 1>&2
    exit 2
  fi
  # Remote check
  if ! git remote get-url "$PUSH_REMOTE" >/dev/null 2>&1; then
    echo "Remote '$PUSH_REMOTE' not found. Use --push-remote to specify." 1>&2
    exit 2
  fi
  echo "Plan to push commit/tag:"
  echo "  Remote : $PUSH_REMOTE"
  echo "  Branch : $PUSH_BRANCH"
  echo "  Tag    : $TAG_NAME"
  if ! confirm "Push to $PUSH_REMOTE/$PUSH_BRANCH and push tag $TAG_NAME?"; then
    echo "Skip pushing."; exit 0
  fi
  set -e
  # Push branch (create upstream if missing)
  if git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
    git push "$PUSH_REMOTE" "$PUSH_BRANCH"
  else
    git push -u "$PUSH_REMOTE" "$PUSH_BRANCH"
  fi
  # Push tag
  git push "$PUSH_REMOTE" "$TAG_NAME"
  echo "Pushed to $PUSH_REMOTE/$PUSH_BRANCH and tag $TAG_NAME."
fi
