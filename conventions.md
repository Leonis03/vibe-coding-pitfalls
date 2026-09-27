# Conventions

*English · [中文（正本 / canonical）](conventions.zh.md) · back to [README](README.md)*

- **These surfaces are pure ASCII only**: directory and file names; system and tool config
  files (**including their comments**, which are written in English); every skill's YAML
  frontmatter (especially `description`, which loads every session and participates in
  trigger matching). Prose docs (`README.zh.md`, `references/*.md`, everything below a
  skill's frontmatter) are in Chinese. Non-ASCII in the wrong place fails **silently and far
  from its cause** -- across the WSL/Windows boundary, in archives, in shell and harness
  parsing.
- **Markdown filenames are lowercase kebab-case**: `wsl-gui-and-ime.md` -- no capitals,
  underscores or spaces. Forensic records and point-in-time snapshots get a `-YYYYMMDD`
  suffix (`etc-diff-analysis-20260330.md`, `pnpm-npm-cleanup-20260920.md`); process docs and
  evergreen docs do not. The only exceptions are **protocol filenames**: `README.md`,
  `README.zh.md`, `SKILL.md`, `SKILL.zh.md`, `AGENTS.md`, `CLAUDE.md`, `TROUBLESHOOTING.md` --
  tools and harnesses look these up literally, so renaming them breaks things.
- **`AGENTS.md` and `CLAUDE.md` exist only at the root.** Harnesses auto-load files with those
  names from subdirectories as instructions, so an *original* that deploys under one of those
  names gets a different name in the repo: `agent/claude-code/claude-global.md` ->
  `~/.claude/CLAUDE.md`, `agent/antigravity/agents-brave-uv.md` -> `~/.gemini/config/AGENTS.md`.
- **Every top-level directory except `tmp/` has a `README.md` index.** Where a directory has a `files/`
  subdirectory, `files/` holds deployable originals and everything else is documentation. An
  original used on more than one platform (the bash / zsh config) lives in a platform-neutral
  directory ([`shell/`](shell/)), not under one platform.
- **Root-level docs are bilingual; subdirectory docs are not.** Every document at the root
  comes as a pair -- `x.md` in English (what GitHub renders by default) and `x.zh.md` as the
  canonical Chinese. Currently three pairs: `README`, `conventions`, `redaction`. Changes
  land in the Chinese version first, then get synced to English -- the pitfall index is
  compressed debugging conclusions, and those are worth getting exactly right in the author's
  first language before translating. **Subdirectory docs are Chinese-only**, with skills as
  the exception: they are read by agents, so both languages earn their keep. The root
  [`AGENTS.md`](AGENTS.md) is another exception: it is the agent entry point, English and
  pure ASCII only, and `CLAUDE.md` is the one line `@AGENTS.md` so Claude Code reads the same
  file. **When the layout, a deploy target, or a "must change together" pair changes, update
  `AGENTS.md` in the same commit** -- a stale map sends agents to the wrong files.
- **The README is a landing page and a router**: header, start here, layout, pitfall index,
  license. Anything substantial that is not needed on every read moves to its own file, with
  one row in the "Start here" table pointing at it -- the same split skills use between
  `SKILL.md` and `references/`. The pitfall index **deliberately stays** in the README: it is
  the most interesting thing here, and moving it out would leave a bare table of contents.
- **Python goes through `uv`, pinned to 3.12**. The system `/usr/bin/python3` is reserved for
  Ubuntu's apt packages; leave it alone.
- **Install skills with `cp`, never `ln -s`**. This tree gets moved between machines, file
  systems and operating systems, and symlinks do not survive that.
- **Sync skills with `bash tools/sync-skills.sh`, not a bare `cp` either.** The repo says
  `<your-home>`, `CourseName` and similar placeholders; the script expands them to real values
  when writing `~/.claude/skills/`, `~/.gemini/config/skills/` or `~/.agents/skills/`, and compares the
  **substituted** bytes when verifying -- so "the hashes match" means "repo == deployed copy,
  modulo redaction". Running it with no arguments is a read-only check. How to write a home
  directory depends on **whether a shell will expand it**: if it will, write `$HOME` (a
  runtime variable shipped as-is, not a placeholder); only where it will not do you write
  `<your-home>` -- just two lines of JSON left in the whole repo. See
  [`agent/skills/README.md`](agent/skills/README.md).
- **Do temporary things in `tmp/`**: backup copies taken before an edit, intermediate script
  output, snippets you want to try, raw command output. Not scattered across the repo root,
  and not in the system `/tmp` either (it is gone after a reboot, right when you want to look
  again tomorrow). The directory is gitignored, `git archive` will not export it, and
  `privacy-gate.sh` **skips** it -- so it can hold real paths and account names without
  turning the gate red every day. `tmp/.gitkeep` is tracked, so a fresh clone still has the
  directory.
- **Run `bash tools/privacy-gate.sh` before publishing.** It only covers known shapes; passing
  is not the same as safe -- `wsl/storage/forensics/` is raw forensic output and has to be read by hand.
  The account names are **not in the script** (putting them there would make the script itself
  the leak); they are read at run time from `tools/.privacy-names`, which is gitignored.
- **Publish with `bash tools/publish.sh`, never a hand-rolled `cp -r`.** This repo is a
  **private primary plus two public snapshots**:
  [`vibe-coding-pitfalls`](https://github.com/Leonis03/vibe-coding-pitfalls) gets the whole tree,
  [`vibe-coding-pitfalls-skills`](https://github.com/Leonis03/vibe-coding-pitfalls-skills) gets
  only the skills (`agent/skills/<name>/` -> `skills/<name>/`, without the third-party
  `find-skills`, plus a README the script generates from each skill's frontmatter). Each public
  repo has its own `.git`; keep a clone of each anywhere you like:

  ```bash
  bash tools/publish.sh <public clone> <skills clone>
  git -C <public clone> status        # read each diff, then add / commit / push in each
  ```

  What the script does -- the steps a manual sync must not skip:
  - **It exports `origin/main`, not `HEAD`.** The checkout here often sits on a feature branch,
    and `git archive HEAD` would publish that branch; `origin/main` is what has been merged.
  - **`git archive`, not `cp -r`**, so `tools/.privacy-names`, `tools/.sync-map` and `tmp/`
    cannot get in.
  - **It runs `privacy-gate.sh` on the export before writing anything**, and writes nothing if
    the gate fails. Rerun with `--skip-gate` only after reading every hit and confirming it is
    expected (say, an account name that is also the public author name).
  - **It wipes before unpacking**, because `tar -x` overwrites but never deletes: a file removed
    here would otherwise linger in public. The wipe spares `.git`.
  - **It does not commit.** Publishing is the one step that cannot be taken back, so commit and
    push stay with a person.

  - **Commits in the public repos carry no AI `Co-Authored-By` trailer** (Claude, Codex,
    Copilot, Gemini and the like): GitHub lists co-authors under the repo's Contributors.
    `publish.sh` uses the [`github-coauthor-scrub`](agent/skills/github-coauthor-scrub/) skill's
    script to install a commit-msg hook in both clones that rejects such a commit, and checks
    the existing history before exporting; if it finds one it stops and prints the rewrite
    (which drops only the AI lines and keeps human co-authors). The private repo and its PRs are
    not bound by this.

  The public repos keep **normal history** by default -- plain `commit` and `push`, never
  `--amend` plus a force push, which would break anyone who has cloned them. **Exception:
  rewriting and force-pushing is allowed** when a commit message carries an AI `Co-Authored-By`,
  when private data or a credential was published and has to leave the history, or in a
  comparable special case. The procedure is fixed: keep a local backup branch before rewriting,
  and push with `git push --force-with-lease=main:<SHA before the rewrite>`, so nobody else's
  new commit gets overwritten. **Then rename the default branch away and back**, or GitHub's
  cached Contributors box keeps the name. The whole sequence is the
  [`github-coauthor-scrub`](agent/skills/github-coauthor-scrub/) skill (`rewrite`, push,
  `refresh`, `verify`). (Precedent: on 2026-09-28 Claude's `Co-Authored-By` was removed
  from six commits; earlier, two amends added the licenses and reformatted a commit message.)
- **Credentials never enter version control.** Tokens that need to be environment variables go
  in `~/.shell_secrets` (`chmod 600`), loaded automatically at the end of `~/.shell_common`.

