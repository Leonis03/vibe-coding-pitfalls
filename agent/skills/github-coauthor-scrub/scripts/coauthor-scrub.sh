#!/usr/bin/env bash
# coauthor-scrub.sh -- remove unwanted Co-authored-by trailers from git history
# and make GitHub's Contributors sidebar forget them.
#
#   coauthor-scrub.sh scan    [-C dir] [-p regex] [--all]   exit 1 if any are found
#   coauthor-scrub.sh rewrite [-C dir] [-p regex] [--all]   local only, never pushes
#   coauthor-scrub.sh hook    [-C dir] [-p regex]           commit-msg hook that rejects them
#   coauthor-scrub.sh refresh <owner/repo>                  rename default branch away and back
#   coauthor-scrub.sh verify  <owner/repo> [-p regex]       read the remote default branch
#
#   -p REGEX  extended regex, matched case-insensitively (the line and the
#             pattern are both lowercased, so avoid \S \W style escapes)
#             against the part of a Co-authored-by line after the key.
#             Default: common AI assistants, see DEFAULT_RE.
#   --all     every local branch and tag instead of the current branch.
#
# Why each step exists is in ../SKILL.md. In one line: GitHub lists every
# co-author under a repo's Contributors, removing the trailer needs a history
# rewrite, and the cached sidebar is rebuilt by renaming the default branch --
# a force-push alone left the name there.

set -uo pipefail

DEFAULT_RE='claude|anthropic|openai|chatgpt|codex|copilot|gemini|cursor|devin|aider'
HOOK_MARK='coauthor-scrub commit-msg hook'
SELF=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")

usage() { sed -n '5,9p' "$SELF" | sed 's/^# *//'; exit "${1:-2}"; }

# --- internal: the message filter git filter-branch runs per commit ----------
# Drops only matching Co-authored-by lines. Trailing newlines are normalised
# only when something was dropped, so an untouched commit keeps its exact
# message and therefore its SHA.
if [ "${1:-}" = __msgfilter ]; then
  exec perl -0pe 'BEGIN { $re = $ENV{SCRUB_RE} }
    if (s/^co-authored-by:[^\n]*(?:$re)[^\n]*\n?//gmi) { s/\n+\z/\n/ }'
fi

cmd=${1:-}; [ -n "$cmd" ] || usage 2; shift
case "$cmd" in -h|--help|help) usage 0 ;; esac
dir=. re=$DEFAULT_RE all=0 repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    -C) dir=${2:?-C needs a directory}; shift 2 ;;
    -p) re=${2:?-p needs a regex}; shift 2 ;;
    --all) all=1; shift ;;
    -h|--help) usage 0 ;;
    -*) echo "unknown option: $1" >&2; usage 2 ;;
    *) repo=$1; shift ;;
  esac
done
case "$re" in *\'*) echo "the regex may not contain a single quote" >&2; exit 2 ;; esac
case "$cmd" in
  scan|rewrite|hook) dir=$(cd "$dir" 2>/dev/null && pwd) || { echo "no such directory: $dir" >&2; exit 2; } ;;
esac
case "$cmd" in scan|rewrite|hook) dir=$(cd "$dir" 2>/dev/null && pwd) || { echo "no such directory" >&2; exit 2; } ;; esac

git_refs() {  # the refs a scan or rewrite covers
  if [ "$all" -eq 1 ]; then REFS=(--branches --tags); else REFS=(HEAD); fi
}

scan() {
  git -C "$dir" rev-parse -q --verify HEAD >/dev/null || { echo "no commits in $dir"; return 0; }
  git_refs
  local out n
  out=$(git -C "$dir" log "${REFS[@]}" --format='%x01%h %s%n%B' | RE="$re" awk '
    BEGIN { re = "^co-authored-by:.*(" tolower(ENVIRON["RE"]) ")" }
    /^\001/ { hdr = substr($0, 2); next }
    tolower($0) ~ re { if (hdr != last) print hdr; last = hdr; print "    " $0 }')
  if [ -z "$out" ]; then
    echo "clean: no Co-authored-by line matching /$re/ in ${REFS[*]} of $dir"
    return 0
  fi
  n=$(printf '%s\n' "$out" | grep -vc '^    ')
  echo "$n commit(s) in ${REFS[*]} of $dir carry a matching Co-authored-by line:"
  printf '%s\n' "$out"
  return 1
}

rewrite() {
  cd "$dir" || exit 2
  git diff --quiet && git diff --cached --quiet \
    || { echo "working tree has changes -- commit or stash them first" >&2; exit 2; }
  if scan >/dev/null; then echo "nothing to rewrite: $(scan)"; return 0; fi

  local stamp branch ref old new
  stamp=$(date +%Y%m%d-%H%M%S)
  local -a targets=() filter_refs=() tagopt=()
  if [ "$all" -eq 1 ]; then
    mapfile -t targets < <(git for-each-ref --format='%(refname)' refs/heads refs/tags)
    filter_refs=(--branches --tags); tagopt=(--tag-name-filter cat)
  else
    branch=$(git symbolic-ref -q --short HEAD) || { echo "detached HEAD -- check out a branch" >&2; exit 2; }
    targets=("refs/heads/$branch"); filter_refs=("$branch")
  fi
  # Backups live outside refs/heads so they are never pushed by accident.
  for ref in "${targets[@]}"; do
    git update-ref "refs/coauthor-backup/$stamp/${ref#refs/}" "$ref"
  done

  SCRUB_RE="$re" FILTER_BRANCH_SQUELCH_WARNING=1 \
    git filter-branch -f --msg-filter "bash '$SELF' __msgfilter" "${tagopt[@]}" -- "${filter_refs[@]}" \
    >/dev/null 2>&1 || { echo "git filter-branch failed; refs are untouched or restorable from refs/coauthor-backup/$stamp/" >&2; exit 1; }

  echo "backup: refs/coauthor-backup/$stamp/"
  echo "rewritten (the tree of every rewritten ref must be identical to its backup):"
  local -a pushes=()
  for ref in "${targets[@]}"; do
    old=$(git rev-parse "refs/coauthor-backup/$stamp/${ref#refs/}")
    new=$(git rev-parse "$ref")
    [ "$old" = "$new" ] && continue
    if git diff --quiet "$old" "$new"; then tree=same; else tree=DIFFERENT; fi
    printf '  %-40s %s -> %s  tree %s\n' "${ref#refs/}" "${old:0:7}" "${new:0:7}" "$tree"
    pushes+=("git push --force-with-lease=$ref:$old origin $ref")
  done
  echo; scan; echo
  echo "Nothing is pushed. When the above looks right:"
  printf '  %s\n' "${pushes[@]}"
  echo "then: bash $SELF refresh <owner/repo>"
  echo "undo (before pushing): git update-ref <ref> refs/coauthor-backup/$stamp/<ref without refs/>"
}

hook() {
  local hooks f
  hooks=$(cd "$dir" && git rev-parse --git-path hooks) || exit 2
  case "$hooks" in /*) ;; *) hooks="$dir/$hooks" ;; esac
  mkdir -p "$hooks"; f="$hooks/commit-msg"
  if [ -e "$f" ] && ! grep -q "$HOOK_MARK" "$f"; then
    echo "$f exists and is not ours -- add this check to it by hand:" >&2
    echo "  grep -qiE '^co-authored-by:.*($re)' \"\$1\" && exit 1" >&2
    exit 1
  fi
  cat > "$f" <<HOOK
#!/bin/sh
# $HOOK_MARK -- GitHub lists every co-author under the repo's Contributors.
if grep -qiE '^co-authored-by:.*($re)' "\$1"; then
  echo "commit-msg: drop the Co-authored-by line matching /$re/ -- this repo takes none (see coauthor-scrub.sh)" >&2
  exit 1
fi
HOOK
  chmod +x "$f"
  echo "installed $f"
}

need_repo() {
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "give <owner/repo>" >&2; usage 2; }
  command -v gh >/dev/null || { echo "needs the GitHub CLI (gh), logged in" >&2; exit 2; }
}

refresh() {
  need_repo
  local def tmp now
  def=$(gh api "repos/$repo" --jq .default_branch) || exit 2
  tmp="$def-contributors-refresh"
  echo "renaming $repo: $def -> $tmp -> $def"
  gh api -X POST "repos/$repo/branches/$def/rename" -f new_name="$tmp" --jq .name >/dev/null || exit 1
  sleep 5
  if ! gh api -X POST "repos/$repo/branches/$tmp/rename" -f new_name="$def" --jq .name >/dev/null; then
    echo "RENAME BACK FAILED -- the default branch is now '$tmp'. Retry:" >&2
    echo "  gh api -X POST repos/$repo/branches/$tmp/rename -f new_name=$def" >&2
    exit 1
  fi
  now=$(gh api "repos/$repo" --jq .default_branch)
  [ "$now" = "$def" ] || { echo "default branch is '$now', expected '$def'" >&2; exit 1; }
  echo "default branch is '$def' again; local clones need nothing beyond 'git fetch --prune'."
  echo "Hard-refresh https://github.com/$repo (Ctrl+Shift+R) and read the Contributors box --"
  echo "no API returns it (the REST contributors list ignores co-authors)."
}

verify() {
  need_repo
  command -v jq >/dev/null || { echo "needs jq" >&2; exit 2; }
  local def hits
  def=$(gh api "repos/$repo" --jq .default_branch) || exit 2
  hits=$(gh api --paginate "repos/$repo/commits?sha=$def&per_page=100" | jq -r --arg re "$re" '
    .[] | . as $c
    | [.commit.message | split("\n")[] | select(test("^co-authored-by:.*(" + $re + ")"; "i"))] as $m
    | select($m | length > 0)
    | "\($c.sha[0:7]) \($c.commit.message | split("\n")[0])\n    \($m | join("\n    "))"')
  echo "commit authors (REST, co-authors not included): $(gh api "repos/$repo/contributors" --jq '[.[].login] | join(", ")')"
  if [ -n "$hits" ]; then
    echo "$repo:$def still has matching Co-authored-by lines:"; printf '%s\n' "$hits"; return 1
  fi
  echo "$repo:$def -- no Co-authored-by line matching /$re/. The sidebar is a cache: see 'refresh'."
}

case "$cmd" in
  scan) scan ;;
  rewrite) rewrite ;;
  hook) hook ;;
  refresh) refresh ;;
  verify) verify ;;
  *) usage 2 ;;
esac
