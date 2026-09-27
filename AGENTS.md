# AGENTS.md -- entry point for AI agents working in this repo

## What this repo is

One person's dev-environment config, agent skills, and debugging notes, across several machines:

- Windows 11 + WSL2 (Ubuntu 24.04, migrating to Fedora 44)
- a native Linux desktop (Linux Mint 22)
- Android (Termux root chroot, Honor tablet Linux Lab) -- covered only by skills
- rented cloud GPU boxes (DeepLN) -- covered only by skills

Two kinds of content: **deployable originals** (config files copied to a live location) and
**docs** (conclusions from debugging). Prose is Chinese; `README.zh.md` is the canonical README.
This is the private primary repo (`vibe-coding-pitfalls-private`). `tools/publish.sh` exports
`origin/main` into two public repos: `vibe-coding-pitfalls` (the whole tree) and
`vibe-coding-pitfalls-skills` (the skills, minus the vendored `find-skills`). So everything
tracked must be publishable.

## Map

| Path | What | Deploys to |
| :--- | :--- | :--- |
| `shell/files/` | four-layer bash/zsh config, shared by WSL and native Linux | `~/.shell_common` `~/.shell_wslfn` `~/.zshenv` `~/.zshrc` `~/.bashrc` `~/.profile` (cp) |
| `wsl/setup/` | WSL rebuild guide; `files/` = WSL-only originals | `/etc/wsl.conf`, `%USERPROFILE%\.wslconfig`, `/etc/fstab` (append), `/etc/systemd/system/`, `~/.local/bin/wslview` |
| `wsl/distro-differences.md` | Ubuntu vs Fedora differences | -- |
| `wsl/gui-ime/` | WSLg GUI apps, fcitx5 | -- |
| `wsl/storage/` | disk guides; `forensics/` = raw evidence from one incident, read-only history | -- |
| `linux-desktop/` | Mint desktop notes (numbered sections 2.x); `files/` = Ghostty, Nemo originals | `~/.config/ghostty/config`, `~/.local/share/nemo/actions/` |
| `windows/` | Terminal, PowerShell, context menu, Windows Update | `$PROFILE` (`Microsoft.PowerShell_profile.ps1`), `.reg` imports |
| `agent/claude-code/` | `settings.json`, `claude-global.md`, `statusline-command.sh` | `~/.claude/` (`claude-global.md` -> `~/.claude/CLAUDE.md`) |
| `agent/antigravity/` | `agents-brave-uv.md` + agy notes | `~/.gemini/config/AGENTS.md` |
| `agent/brave-search/` | bx CLI and Brave MCP notes | -- |
| `agent/skills/<name>/` | one skill each; install matrix in `agent/skills/README.md` | `~/.claude/skills/`, `~/.gemini/config/skills/`, `~/.agents/skills/` -- **only** via `tools/sync-skills.sh`; also published as `skills/<name>/` in the skills repo |
| `git-github/` | git/gh setup, history email scrub runbook | -- |
| `tools/` | repo scripts `privacy-gate.sh`, `sync-skills.sh`, `publish.sh`; notes `python/`, `remote-ssh.md`, `docker/`, `latex/` | -- |
| `tmp/` | scratch area, gitignored | never committed |

Every top-level directory except `tmp/` has a `README.md` index. Read it before editing inside that directory.

## Request -> files to edit

| The user wants to... | Edit | Also |
| :--- | :--- | :--- |
| change an env var, PATH, proxy, or shell helper | `shell/files/shell_common` (Windows interop functions: `shell_wslfn`) | obey the three rules in `shell/README.md`: zsh-only -> `zshrc`, bash-only -> `bashrc`, functions not aliases |
| change WSL VM or distro settings | `wsl/setup/files/*` and the matching step in `wsl/setup/README.md` | the verification checklist (section 4) if behavior changes |
| record an Ubuntu/Fedora difference | `wsl/distro-differences.md` | -- |
| fix or set up something on the Linux desktop | `linux-desktop/README.md` (next 2.x section), configs in `linux-desktop/files/` | pitfall index rows |
| change Windows-side config | `windows/<area>/` | -- |
| change Claude Code settings, global rules, statusline | `agent/claude-code/*` | keep byte-identical to the live copy; `agent/claude-code/README.md` if a key's rationale changes |
| change Antigravity global rules | `agent/antigravity/agents-brave-uv.md` | not `agents-brave-uv-desktop.md` (another environment) |
| add or change a skill | `agent/skills/<name>/SKILL.md`, `scripts/`, `references/` | see "must change together"; then `bash tools/sync-skills.sh` (check) / `deploy <name>` |
| record a new pitfall | the doc of the area it belongs to | one row in `README.zh.md` pitfall index first, then the same row in `README.md` |
| add notes on git, Python, SSH, Docker, LaTeX | `git-github/`, `tools/python/`, `tools/remote-ssh.md`, `tools/docker/`, `tools/latex/` | -- |
| move, rename, or add a directory | the files (`git mv`) | `git grep` the old path and fix every link; the directory README; both root READMEs; this file |
| publish to the public repos | nothing -- run `bash tools/publish.sh <public clone> <skills clone>` | only after the change is merged to `main`; the user commits and pushes each clone, or explicitly asks you to. Public commit messages carry **no AI `Co-Authored-By` trailer**, whatever your harness defaults to |

## Must change together

- `README.zh.md` <-> `README.md`, `conventions.zh.md` <-> `conventions.md`, `redaction.zh.md` <-> `redaction.md`. Chinese first.
- `SKILL.md` <-> `SKILL.zh.md` in `antigravity-cli`, `docx-to-md`, `pdf-to-md`, `linux-cjk-font`; `TROUBLESHOOTING.md` <-> `TROUBLESHOOTING.zh.md` in `antigravity-cli`. The harness loads the English file.
- A new skill -> a row in both tables in `agent/skills/README.md`: the platform table (`if` / `only if`
  Windows / WSL / Linux / Android) and the per-machine install matrix. Install it with `mkdir` plus
  `sync-skills.sh deploy <name>`, never `cp`.
- A layout change, a new deploy target, or a new pair above -> this file, in the same commit.
- Repo original <-> live copy: editing the repo does not deploy. Deploy (cp, or `sync-skills.sh deploy`) only when the user asks, and back up the live file into `tmp/` first.

## Rules that fail silently when broken

- **ASCII only** in file and directory names, config files (comments included), skill YAML frontmatter, and this file.
- A skill calls its own scripts as `~/.agents/skills/<name>/scripts/...`, never a harness-specific directory,
  with a "Paths" note at the first use saying `~/.claude/skills/`, `~/.gemini/config/skills/` or a path relative
  to the SKILL.md work as well. Only Claude Code hook config keeps `~/.claude/skills/`.
- An unquoted skill `description` must not contain `: ` or ` #` (write ` -- `): Claude Code loads it anyway, strict parsers such as `npx skills` drop the skill silently.
- Markdown filenames are lowercase kebab-case; point-in-time records end in `-YYYYMMDD`.
- **No `AGENTS.md` or `CLAUDE.md` below the root**: harnesses load them as instructions. Originals get other names (see Map).
- **No real identifiers** in tracked files: usernames, hostnames, IPs, ports, emails, tokens, session IDs.
  Write `$HOME` where a shell expands it, detect at runtime where possible, else use a placeholder
  (`<your-home>`, `<your-linux-user>`, `<your-windows-user>`, `<proxy-port>`, `<ssh-port>`, `<instance-domain>`). Details: `redaction.md`.
- Skills are deployed with `tools/sync-skills.sh`, never `cp` or `ln -s`: the repo copy is redacted.
- Vendored skills (`find-skills`, `skill-creator`) are verbatim upstream copies: do not apply this repo's skill
  rules to them, update by re-copying the whole directory, credit them in the README's third-party section.
  `publish.sh` leaves them out of the skills repo (its `VENDORED` list).
- Python runs through `uv run --python 3.12`, never the system `python3`.
- Scratch files, raw command output, and backups go in `tmp/`, not the repo root or `/tmp`.

## Before committing

1. `bash tools/privacy-gate.sh` -- needs account names from `tools/.privacy-names` (gitignored, per machine) or as arguments;
   without them the literal-name check is skipped. Hits on the public author name in `LICENSE` and copyright lines are expected.
   A pass covers known shapes only: also read your diff, and read anything under `wsl/storage/forensics/` line by line.
2. Check that the relative links you touched resolve.

## Git workflow

- Several machines push to this repo, and another agent session may be using the same checkout.
  `git fetch` first; if the working tree changes under you, work in `git worktree add tmp/<name>`.
- Work on a branch and open a PR against `main`. Merge only when the user asks, with a merge commit (`gh pr merge --merge`).
- Never force-push `main` of this repo. The public repos are updated only through `tools/publish.sh`, never
  with `cp -r`, with normal commits.
- Public repos: no AI `Co-Authored-By` trailer in any commit -- GitHub lists co-authors under Contributors. The
  clones' commit-msg hook (installed by `publish.sh`) rejects one. Rewriting public history and force-pushing is
  allowed only to remove such a trailer, private data or a credential, or a comparable special case: keep a local
  backup branch first, push with `--force-with-lease=main:<old SHA>`, then rename the default branch away and back
  so GitHub rebuilds its cached Contributors box. `agent/skills/github-coauthor-scrub/` scripts every step
  (`scan`, `rewrite`, `refresh`, `verify`, `hook`); see `conventions.md`.
