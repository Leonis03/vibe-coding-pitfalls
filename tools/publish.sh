#!/usr/bin/env bash
# publish.sh -- export origin/main of this private repo into the public clones.
#
#   bash tools/publish.sh <public-clone> [<skills-clone>]
#   bash tools/publish.sh --skip-gate <public-clone> [<skills-clone>]
#
#   <public-clone>  clone of Leonis03/vibe-coding-pitfalls. Receives the whole
#                   tree.
#   <skills-clone>  clone of Leonis03/vibe-coding-pitfalls-skills. Receives
#                   agent/skills/<name>/ as skills/<name>/ (vendored skills
#                   left out), a README.md generated from each SKILL.md's
#                   frontmatter, and both licenses.
#
# It never commits or pushes. Review `git -C <clone> status` and the diff,
# then commit and push by hand -- publishing is the one step that cannot be
# taken back. Exit 0 = exported, 1 = privacy gate failed, 2 = usage/setup.
#
# WHY origin/main AND NOT HEAD
#
# The private checkout is usually on a feature branch, and more than one
# machine pushes to it. `git archive HEAD` would publish whatever branch
# happens to be checked out here; origin/main is what has been reviewed.
#
# WHY git archive, AND WHY WIPE FIRST
#
# git archive exports tracked files only, so tools/.privacy-names,
# tools/.sync-map and tmp/ cannot get in (cp -r would copy them). And tar -x
# overwrites but never deletes: without the wipe, a file removed here would
# live on in the public repo. The wipe spares .git, or it would take the
# repository with it.
#
# THE GATE
#
# The export is scanned by tools/privacy-gate.sh before anything is written.
# Account names come from this checkout's tools/.privacy-names, as usual. A
# pass covers known shapes only, so --skip-gate exists for the case where you
# have read every hit and they are expected (e.g. a name that is also the
# public author name) -- not for skipping the read.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
REPO=$PWD
REF=origin/main
VENDORED=(find-skills)   # third-party skills: not ours to republish alone

skip_gate=0
if [ "${1:-}" = "--skip-gate" ]; then skip_gate=1; shift; fi
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  sed -n '4,5p' "$0" | sed 's/^# *//'
  exit 2
fi
PUB=$(cd "$1" 2>/dev/null && pwd) || { echo "no such directory: $1" >&2; exit 2; }
SKL=""
if [ "$#" -eq 2 ]; then
  SKL=$(cd "$2" 2>/dev/null && pwd) || { echo "no such directory: $2" >&2; exit 2; }
fi
for d in "$PUB" ${SKL:+"$SKL"}; do
  [ -e "$d/.git" ] || { echo "not a git clone: $d" >&2; exit 2; }
  case "$d/" in
    "$REPO"/tmp/*) ;;   # a scratch clone under tmp/ is fine
    "$REPO"/*) echo "refusing to publish into this repo: $d" >&2; exit 2 ;;
  esac
done

git fetch -q origin || { echo "git fetch failed" >&2; exit 2; }
echo "exporting $REF = $(git rev-parse --short "$REF")"

STAGE=$(mktemp -d "$REPO/tmp/publish-XXXXXX") || exit 2
trap 'rm -rf "$STAGE"' EXIT
git archive "$REF" | tar -x -C "$STAGE"

# --- gate -------------------------------------------------------------------
names=""
if [ -f tools/.privacy-names ]; then
  names=$(sed 's/#.*//' tools/.privacy-names | tr -s '[:space:]' ' ')
fi
if ! ( cd "$STAGE" && PRIVACY_NAMES="$names" bash tools/privacy-gate.sh ) > "$STAGE.gate" 2>&1; then
  grep -vE '^\s+ok ' "$STAGE.gate"
  if [ "$skip_gate" -eq 0 ]; then
    echo; echo "privacy gate failed -- nothing written. Read the hits; rerun with --skip-gate only if every one is expected."
    rm -f "$STAGE.gate"; exit 1
  fi
  echo; echo "--skip-gate: continuing past the hits above"
else
  grep -E '^  SKIP|^RESULT' "$STAGE.gate" | sed 's/^ */gate: /'
fi
rm -f "$STAGE.gate"

wipe() { find "$1" -mindepth 1 -maxdepth 1 -not -name .git -exec rm -rf {} +; }

# --- whole tree -------------------------------------------------------------
wipe "$PUB"
cp -a "$STAGE/." "$PUB/"
echo "wrote $PUB"
# Belt and braces: nothing written may be something .gitignore exists to hide.
ignored=$(cd "$PUB" && find . -type f -not -path './.git/*' | git check-ignore --stdin)
[ -z "$ignored" ] || { printf 'WARNING, gitignored files in the export:\n%s\n' "$ignored"; }

# --- skills -----------------------------------------------------------------
# Frontmatter description, one line: handles a plain value and a folded or
# literal block (`description: >-` followed by indented lines).
describe() {
  awk '
    /^---[[:space:]]*$/ { if (++c == 2) exit; next }
    c == 1 {
      if (fold) { if ($0 ~ /^[ \t]+[^ \t]/) { sub(/^[ \t]+/, ""); d = d (d == "" ? "" : " ") $0; next } fold = 0 }
      if ($0 ~ /^description:/) {
        v = $0; sub(/^description:[ \t]*/, "", v)
        if (v ~ /^[>|][-+]?$/) { fold = 1; d = "" } else d = v
      }
    }
    END { gsub(/^["\047]|["\047]$/, "", d); print d }' "$1"
}
# First sentence: up to the first ". " -- "e.g." and "3.x" do not end one.
first_sentence() { sed -E 's/^(([^.]|\.[^ ]|e\.g\. )*\.) .*/\1/'; }

if [ -n "$SKL" ]; then
  wipe "$SKL"
  mkdir -p "$SKL/skills"
  cp "$STAGE/LICENSE" "$STAGE/LICENSE-DOCS" "$SKL/"
  rows=""
  for dir in "$STAGE"/agent/skills/*/; do
    name=$(basename "$dir")
    skip=0; for v in "${VENDORED[@]}"; do [ "$name" = "$v" ] && skip=1; done
    [ "$skip" -eq 1 ] && continue
    cp -a "$dir" "$SKL/skills/$name"
    # Escape | (table cell) and $ (GitHub would render $...$ as math).
    desc=$(describe "$dir/SKILL.md" | first_sentence | sed -e 's/|/\\|/g' -e 's/\$/\\$/g')
    rows+="| [\`$name\`](skills/$name/SKILL.md) | $desc |"$'\n'
  done
  cat > "$SKL/README.md" <<EOF
# vibe-coding-pitfalls-skills

Agent skills for Claude Code and Antigravity (\`agy\`). Most of them encode a failure that
had already cost real time, so the agent does not walk into it again. They are exported from the same source as
[vibe-coding-pitfalls](https://github.com/Leonis03/vibe-coding-pitfalls), where the
pitfall index explains why each one exists; a few skills link to docs there.

| Skill | What it is for |
| :--- | :--- |
${rows}
## Install

\`\`\`bash
npx skills add Leonis03/vibe-coding-pitfalls-skills --list                      # see what is here
npx skills add Leonis03/vibe-coding-pitfalls-skills --skill <name> -g --copy    # one skill, user-level
\`\`\`

\`--copy\` copies the files into the agent directories instead of symlinking them. Copying by hand
also works: \`skills/<name>/\` goes to \`~/.claude/skills/<name>/\` or
\`~/.gemini/config/skills/<name>/\`.

**Placeholders.** The skills are redacted. Values in angle brackets (\`<your-home>\`,
\`<proxy-port>\`, \`<ssh-port>\`, \`<instance-domain>\`, ...) and \`CourseName\` stand for
your own values; replace them after installing. \`\$HOME\` is a real shell variable and stays
as it is.

Some skills are machine-specific by nature (\`honor-linuxlab\`, \`deepln-setup\`,
\`compress-wsl-space\`); read the SKILL.md before installing them.

## License

Code (\`scripts/\`) is [MIT](LICENSE); documentation (every \`.md\`) is
[CC BY 4.0](LICENSE-DOCS).

Generated by \`tools/publish.sh\` from $(git rev-parse --short "$REF") -- edit the source, not this repo.
EOF
  echo "wrote $SKL ($(printf '%s' "$rows" | grep -c '^|') skills)"
fi

echo
echo "Nothing is committed. Review, then in each clone: git add -A && git commit && git push"
