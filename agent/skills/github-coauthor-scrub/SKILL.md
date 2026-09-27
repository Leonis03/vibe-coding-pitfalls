---
name: github-coauthor-scrub
description: Remove unwanted co-authors from a GitHub repo's commit history and from its Contributors box -- AI assistants (Claude, Copilot, Codex, Gemini, Cursor) added through Co-authored-by trailers, or any named person. Use when a repo page lists claude or another bot under Contributors, when commits carry an unwanted Co-authored-by line, before making a repo public, or when the user wants AI attribution kept out of commits. Covers scanning, rewriting history while keeping human co-authors, force-push with lease, the default-branch rename that makes GitHub rebuild its cached Contributors box (a force-push alone leaves the name), verification, and a commit-msg hook plus the Claude Code setting that stop it coming back.
---

# Scrub co-authors from a GitHub repo

GitHub credits every `Co-authored-by: Name <email>` trailer to the account that owns the email,
and lists that account in the repo's **Contributors** box. Claude Code's default commit
attribution ends with `Co-Authored-By: Claude ... <noreply@anthropic.com>`, which is the
`claude` account -- so a repo whose commits were written with Claude shows "claude Claude" next
to the owner. Removing it takes three separate things, and skipping any one of them leaves the
name visible:

1. the trailer must leave **every reachable commit** (a history rewrite, then a force-push);
2. GitHub's **cached** Contributors box must be rebuilt (rename the default branch and back);
3. new commits must stop adding it (harness setting + commit-msg hook).

Everything below uses `scripts/coauthor-scrub.sh`.

> **Paths.** Commands below use `~/.agents/skills/github-coauthor-scrub/`. Any installed copy works: use `~/.claude/skills/github-coauthor-scrub/`, `~/.gemini/config/skills/github-coauthor-scrub/`, or a path relative to this SKILL.md instead -- only one of the three needs to exist.

```bash
S=~/.agents/skills/github-coauthor-scrub/scripts/coauthor-scrub.sh
bash $S scan    -C <clone> [--all] [-p REGEX]   # which commits carry a matching trailer; exit 1 if any
bash $S rewrite -C <clone> [--all] [-p REGEX]   # backup refs + rewrite; prints the push commands
bash $S refresh <owner/repo>                    # rename default branch away and back
bash $S verify  <owner/repo> [-p REGEX]         # read the remote default branch through the API
bash $S hook    -C <clone> [-p REGEX]           # commit-msg hook that rejects the trailer
```

`-p` defaults to common AI assistants
(`claude|anthropic|openai|chatgpt|codex|copilot|gemini|cursor|devin|aider`). To remove a person
instead, pass their name or email, e.g. `-p 'jane doe|jane@example\.com'`. The match runs on
the `Co-authored-by:` line only, so "Claude Code" in a commit's prose is never touched.

## Before you start: decide the blast radius

A rewrite gives every rewritten commit, and every commit after it, a new SHA. Settle these
with the user first -- they are the part that cannot be taken back once pushed:

- **Which refs.** Default is the current branch. `--all` covers every local branch and tag;
  use it when other branches or tags also contain the trailer (check with `scan --all` after
  fetching every branch: `git fetch origin '+refs/heads/*:refs/remotes/origin/*'` and check
  out the ones you need locally).
- **Who else has a clone.** After the force-push they must `git fetch && git reset --hard
  origin/<branch>` (after saving local work) or re-clone. Open PRs based on old commits need
  a rebase. Forks keep the old commits and are out of your reach.
- **Signed commits** lose their signatures when rewritten.
- **The repo's own rules.** If it has a "never force-push" convention, this is the exception to
  get agreed explicitly, not assumed.

## Steps

**1. Stop the source first**, or the next commit brings it back.

- Claude Code (2.1.x): in `~/.claude/settings.json` (or the project's `.claude/settings.json`)
  set `"attribution": {"commit": "", "pr": ""}` -- an empty string hides the attribution.
  The older `"includeCoAuthoredBy": false` still works but is deprecated.
- Other assistants: find their equivalent setting; the hook below catches whatever slips through.
- A user-level or project `CLAUDE.md` rule also works, but a setting and a hook do not rely on
  the model remembering.

**2. Scan.** `bash $S scan -C <clone> --all`. It prints each commit and the matching line.
Nothing found and the name still shows? Go to step 5 -- it is the cache.

**3. Rewrite.** `bash $S rewrite -C <clone> [--all]`. It refuses a dirty working tree, saves
every ref it will touch under `refs/coauthor-backup/<timestamp>/` (outside `refs/heads`, so a
normal push never publishes them), and runs `git filter-branch` with a message filter that:

- drops only the matching `Co-authored-by` lines -- human co-authors stay;
- keeps authors, committers and dates;
- leaves every commit without a match byte-identical, so its SHA does not change.

It then prints, per rewritten ref, `old -> new  tree same`. **The tree must be `same`**: only
messages may differ. Read the rescan it prints, then the push commands.

**4. Push with a lease.** Run the printed commands, e.g.

```bash
git push --force-with-lease=refs/heads/main:<old sha> origin refs/heads/main
```

The explicit old SHA makes the push fail if anyone pushed in the meantime, instead of silently
discarding their work. Never use `--mirror` here: it would publish `refs/coauthor-backup/`.

**5. Rebuild GitHub's Contributors cache.** `bash $S refresh <owner/repo>`. It renames the
default branch to `<name>-contributors-refresh` and back after 5 s, then checks the default is
the original name again.

Measured on 2026-09-28: after the rewrite and force-push, and even after a further ordinary
push, the Contributors box still listed `claude`; this rename made it disappear within minutes
(the same fix is the accepted answer in GitHub Community discussion #191565). The rename needs
admin rights. GitHub retargets open PRs and moves branch protection with it; local clones need
only `git fetch --prune`, because the name ends up unchanged.

**6. Verify.** `bash $S verify <owner/repo>` reads the default branch's commits through the API
and exits 1 if any matching trailer is left. It cannot read the Contributors box itself: the
REST `contributors` endpoint lists commit **authors only** and never showed `claude`, even while
the page did. So finish by hard-refreshing the repo page (Ctrl+Shift+R) and reading the box.

**7. Keep it from coming back.** `bash $S hook -C <clone>` installs a `commit-msg` hook that
rejects a matching trailer; human co-authors still pass. It will not overwrite a hook it did not
write -- it prints the one-line check to add by hand instead. Hooks live in the clone, not in
the repo, so install it in every clone that commits to the repo.

## What is left afterwards

- **The old commits still exist on GitHub** and open by SHA (`/commit/<old sha>`, or
  `gh api repos/<owner>/<repo>/commits/<old sha>`) until GitHub garbage-collects them. They no
  longer count as contributions to the repo. To have them purged sooner, ask GitHub Support to
  remove cached views and run garbage collection -- the same request as for removing sensitive
  data.
- **Forks and PR refs** (`refs/pull/*`) keep the old commits; you cannot rewrite those.
- The co-author's own profile loses the credit once the commits are unreachable; nothing to do.

## Undo

Before pushing: `git update-ref refs/heads/<branch> refs/coauthor-backup/<timestamp>/heads/<branch>`
(tags: `refs/tags/<tag>` from `.../tags/<tag>`). After pushing: push the backup SHA back with
another `--force-with-lease`. Delete the backups when done:
`git for-each-ref --format='%(refname)' refs/coauthor-backup | xargs -n1 git update-ref -d`.

## Pitfalls

| Symptom | Cause | Fix |
| :--- | :--- | :--- |
| History is clean, Contributors still shows the bot | The box is a cache; a force-push or new push does not rebuild it | `refresh` (step 5) |
| `gh api .../contributors` shows only you, the page shows the bot too | The REST list counts authors, the page also counts co-authors | Judge by the page, not the API |
| The name returns after a clean-up | The harness still adds the trailer | Step 1 setting + step 7 hook |
| `filter-branch` refuses to start | Uncommitted changes | Commit or stash, then rerun |
| A tag still points at an old commit | Only the current branch was rewritten | `rewrite --all`, push the tag with its lease |
| Other people's pushes vanished | Plain `--force` | Always `--force-with-lease=<ref>:<old sha>` |
