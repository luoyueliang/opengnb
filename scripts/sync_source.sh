#!/usr/bin/env bash
set -euo pipefail

# Sync external source repo into local ./src, commit, tag, and record mapping.
#
# Usage:
#   scripts/sync_source.sh [--subdir path/in/repo] [--yes]
#
# Notes:
# - Creates/updates ./src with contents from the external repo (subdir if provided).
# - Commits the change with a message referencing source repo/ref/sha.
# - Creates a local tag: src-sync/<version|ref> (with timestamp suffix if exists).
# - Appends a JSON line to sources/history.ndjson for traceability.

usage() {
  echo "Usage: $0 [--subdir <path>] [--yes]" 1>&2
  echo "       Interactive wizard will list source tags from gnbdev/opengnb and target tags in this repo, and optionally push at the end." 1>&2
  exit 1
}

REPO="gnbdev/opengnb"; REF=""; SUBDIR="."; VERSION=""; ASSUME_YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subdir) SUBDIR="$2"; shift 2 ;;
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
MADE_COMMIT=0
if git diff --cached --quiet; then
  echo "No changes detected in src; nothing to commit."
  SRC_COMMIT=$(git rev-parse --short=12 HEAD)
else
  MSG="sync(src): ${REPO}@${REF} (${SRC_SHA}) -> src/"
  if [[ -n "$VERSION" ]]; then MSG+=" [version ${VERSION}]"; fi
  git commit -m "$MSG"
  SRC_COMMIT=$(git rev-parse --short=12 HEAD)
  MADE_COMMIT=1
fi

# Prepare tag name (use target tag chosen by user) and create/move tag
TAG_NAME="$VERSION"
if git rev-parse -q --verify "refs/tags/$TAG_NAME" >/dev/null; then
  OLD_TAG_COMMIT=$(git rev-parse --short=12 "refs/tags/$TAG_NAME^{commit}" || true)
  echo "Tag '$TAG_NAME' already exists at $OLD_TAG_COMMIT."
  if confirm "Move tag '$TAG_NAME' to $SRC_COMMIT? (a backup tag will be created)"; then
    BK_TAG="backup/${TAG_NAME}-$(date +%Y%m%d%H%M%S)"
    git tag "$BK_TAG" "refs/tags/$TAG_NAME" -m "Backup of ${TAG_NAME} before retag"
    git tag -fa "$TAG_NAME" "$SRC_COMMIT" -m "Source sync from ${REPO}@${REF} (${SRC_SHA})"
    echo "Moved tag '$TAG_NAME' (backup saved as '$BK_TAG')."
  else
    echo "Aborted retagging. Exiting."
    exit 1
  fi
else
  git tag -a "$TAG_NAME" "$SRC_COMMIT" -m "Source sync from ${REPO}@${REF} (${SRC_SHA})"
  echo "Created tag '$TAG_NAME' -> $SRC_COMMIT"
fi

# Diffstat for record (from previous HEAD to SRC_COMMIT if we committed)
DIFFSTAT=""
if [[ -n "$DIFF_PREV" ]]; then
  if [[ $MADE_COMMIT -eq 1 ]]; then
    DIFFSTAT=$(git --no-pager diff --stat "$DIFF_PREV..$SRC_COMMIT" | tr '\n' ' ' | sed -E 's/\s+/ /g')
  else
    DIFFSTAT="(no changes)"
  fi
fi

# Record history (ndjson) and commit as a separate history commit
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat >> "$HIST_FILE" <<EOF
{"timestamp":"$TS","source":{"repo":"$REPO","ref":"$REF","commit":"$SRC_SHA","subdir":"$SUBDIR"},"local":{"commit":"$SRC_COMMIT","tag":"$TAG_NAME"},"paths":{"dest":"src"},"diffstat":"$DIFFSTAT"}
EOF
git add "$HIST_FILE"
git commit -m "chore(history): record source sync for ${REPO}@${REF} -> ${TAG_NAME}"
LOCAL_SHA=$(git rev-parse --short=12 HEAD)

echo "Done. Source commit: $SRC_COMMIT, tag: $TAG_NAME, history commit: $LOCAL_SHA"
echo "History appended to: $HIST_FILE"

# Interactive push prompt (no CLI flags) 
if is_tty; then
  echo
  echo "Do you want to push the branch and tag now?"
  if confirm "Push to remote?"; then
    # Determine branch
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)
    if [[ "$CURRENT_BRANCH" == "HEAD" || -z "$CURRENT_BRANCH" ]]; then
      # List local branches
      echo "Select a local branch to push:" 
      LOCAL_BRANCHES=()
      while IFS= read -r _b; do [[ -n "$_b" ]] && LOCAL_BRANCHES+=("$_b"); done < <(git for-each-ref --format='%(refname:short)' refs/heads/ | sort)
      if [[ ${#LOCAL_BRANCHES[@]} -eq 0 ]]; then echo "No local branches found"; exit 2; fi
      for i in "${!LOCAL_BRANCHES[@]}"; do echo "  $((i+1))) ${LOCAL_BRANCHES[$i]}"; done
      read -r -p "Enter choice [1-${#LOCAL_BRANCHES[@]}]: " lsel || true
      if [[ "$lsel" =~ ^[0-9]+$ ]] && (( lsel >=1 && lsel <= ${#LOCAL_BRANCHES[@]} )); then
        PUSH_BRANCH="${LOCAL_BRANCHES[$((lsel-1))]}"
      else
        echo "Invalid choice"; exit 2
      fi
    else
      PUSH_BRANCH="$CURRENT_BRANCH"
    fi

    # Determine remote (default origin if present)
    DEFAULT_REMOTE="origin"
    if git remote get-url "$DEFAULT_REMOTE" >/dev/null 2>&1; then
      PUSH_REMOTE="$DEFAULT_REMOTE"
    else
      REMOTES=()
      while IFS= read -r _r; do [[ -n "$_r" ]] && REMOTES+=("$_r"); done < <(git remote)
      if [[ ${#REMOTES[@]} -eq 0 ]]; then echo "No git remotes configured"; exit 2; fi
      echo "Select a remote to push:" 
      for i in "${!REMOTES[@]}"; do echo "  $((i+1))) ${REMOTES[$i]}"; done
      read -r -p "Enter choice [1-${#REMOTES[@]}]: " rsel || true
      if [[ "$rsel" =~ ^[0-9]+$ ]] && (( rsel >=1 && rsel <= ${#REMOTES[@]} )); then
        PUSH_REMOTE="${REMOTES[$((rsel-1))]}"
      else
        echo "Invalid choice"; exit 2
      fi
    fi

    echo "Plan to push:"
    echo "  Remote : $PUSH_REMOTE"
    echo "  Branch : $PUSH_BRANCH"
    echo "  Tag    : $TAG_NAME"
    if confirm "Confirm push to $PUSH_REMOTE/$PUSH_BRANCH and tag $TAG_NAME?"; then
      # Push branch (create upstream if missing)
      if git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
        git push "$PUSH_REMOTE" "$PUSH_BRANCH"
      else
        git push -u "$PUSH_REMOTE" "$PUSH_BRANCH"
      fi
      git push -f "$PUSH_REMOTE" "$TAG_NAME"
      echo "Pushed to $PUSH_REMOTE/$PUSH_BRANCH and tag $TAG_NAME."
    else
      echo "Skip pushing."
    fi
  else
    echo "Skipping push by user choice."
  fi
else
  echo "Non-interactive shell; skipping push."
fi
