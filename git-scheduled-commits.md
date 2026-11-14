# Git Scheduled Commits — Split Changes Across Contribution Graph Days

A step-by-step guide for splitting a set of changes into multiple commits with
**chosen dates**, so they light up your GitHub contribution graph on the days
you plan (e.g., 3 commits today + 7 commits tomorrow).

The date that matters is the **author date**, which is fully controllable per
commit. A push carries many commits but has no date of its own — the graph
reads each commit's own date.

<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li><a href="#how-the-contribution-graph-counts-commits">How The Contribution Graph Counts Commits</a></li>
    <li><a href="#prerequisites">Prerequisites</a></li>
    <li><a href="#usage">Usage — Step by Step</a></li>
    <li><a href="#full-example">Full Example — 10 Changes: 3 Today + 7 Tomorrow</a></li>
    <li><a href="#variants">Variants</a></li>
    <li><a href="#verification">Verification</a></li>
    <li><a href="#notes-and-caveats">Notes and Caveats</a></li>
    <li><a href="#troubleshooting">Troubleshooting</a></li>
  </ol>
</details>

## How The Contribution Graph Counts Commits

- GitHub lights a square using the commit's **author date** (not the push date).
- Requirements for a commit to count: it lands on the repository's **default
  branch** (`main`), the author email matches a **verified email** on the
  account, and the repo is **not a fork**.
- A future-dated commit pushed today does **not** light the square immediately:
  the graph only renders up to today. The square lights up **when that date
  actually arrives**.
- Every commit can carry its own date independently — splitting N changes
  across N days is just setting the date per commit before committing it.

## Prerequisites

1. **Git installed** (Git Bash on Windows recommended — the examples use bash syntax)
2. **Repository cloned with `main` as default branch**
3. **`git config user.email` matches your verified GitHub email**

Check before starting:

```bash
git config user.email
git remote -v
git status --short        # the changes you plan to split
```

## Usage — Step by Step

### Step 1 — Make your changes

Work as usual. In this example you end up with 10 modified files:

```bash
git status --short
# M docs/a.md, M docs/b.md, ... (10 files)
```

### Step 2 — Plan the split

Decide which changes go to "today" and which go to "tomorrow" (or any date),
and how many commits per batch. Example plan:

| Batch | Commits | Author date | Files |
|-------|---------|-------------|-------|
| 1 | 3 | today (2026-11-13) | files 1–6 |
| 2 | 7 | tomorrow, 09:00 (2026-11-14T09:00:00+07:00) | files 7–10 |

### Step 3 — Commit the "today" batch (normal commits)

```bash
git add docs/a.md docs/b.md
git commit -m "docs: add setup guide"

git add docs/c.md
git commit -m "feat: add feature section"

git add docs/d.md docs/e.md
git commit -m "docs: extend examples"
```

No special variables needed — a normal commit is dated "now".

### Step 4 — Commit the "tomorrow" batch (backdated commits)

Set both dates via environment variables, per commit:

```bash
GIT_AUTHOR_DATE="2026-11-14T09:00:00+07:00" \
GIT_COMMITTER_DATE="2026-11-14T09:00:00+07:00" \
git add docs/f.md && git commit -m "feat: add scheduled commits doc"
```

> On **PowerShell**, environment prefixes don't work the same way. Use:
>
> ```pwsh
> $env:GIT_AUTHOR_DATE  = "2026-11-14T09:00:00+07:00"
> $env:GIT_COMMITTER_DATE = "2026-11-14T09:00:00+07:00"
> git add docs/f.md; git commit -m "feat: add scheduled commits doc"
> # repeat per commit, then clean up:
> Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE
> ```

Repeat for every commit in the batch — same date, or different dates per
commit if you want them spread over several days.

### Step 5 — Verify the dates before pushing

```bash
git log --format=fuller -10
# AuthorDate: Thu Nov 13 ...   ← batch 1
# CommitDate: Thu Nov 13 ...
# AuthorDate: Fri Nov 14 09:00:00 2026 +07:00   ← batch 2
```

### Step 6 — Push once

```bash
git push origin main
```

### Step 7 — What you will see

- Batch 1 squares light up within minutes of the push.
- Batch 2 squares stay dark until 2026-11-14 arrives, then light up
  automatically — nothing left to run or push.

## Full Example — 10 Changes: 3 Today + 7 Tomorrow

Complete copy-paste flow (Git Bash, adjust file names and messages):

```bash
# ---- batch 1: today (2026-11-13) ----
git add change-01.md change-02.md && git commit -m "feat: add part one"
git add change-03.md              && git commit -m "feat: add part two"
git add change-04.md change-05.md && git commit -m "feat: add part three"

# ---- batch 2: tomorrow (2026-11-14 09:00 WIB) ----
export GIT_AUTHOR_DATE="2026-11-14T09:00:00+07:00"
export GIT_COMMITTER_DATE="2026-11-14T09:00:00+07:00"

git add change-06.md && git commit -m "feat: add part four"
git add change-07.md && git commit -m "feat: add part five"
git add change-08.md && git commit -m "feat: add part six"
git add change-09.md && git commit -m "feat: add part seven"
git add change-10.md && git commit -m "feat: add part eight"

unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE   # important cleanup!

# ---- ship it ----
git push origin main
```

> `export` keeps the dates for every commit in the batch in one go;
> **do not forget `unset`** — otherwise your next normal commits carry the
> backdated date too.

## Variants

**All changes to one chosen day:**

```bash
export GIT_AUTHOR_DATE="2026-11-20T10:00:00+07:00"
export GIT_COMMITTER_DATE="2026-11-20T10:00:00+07:00"
git add -A && git commit -m "feat: weekend batch"
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
git push origin main
```

**One commit per change (10 changes = 10 commits):** repeat `git add <one-file>`
+ `git commit` per file, alternating the date variables per batch.

**Filling a past gap (history reconstruction):** same commands with a past
date, e.g. `"2026-10-05T09:00:00+07:00"`.

## Verification

```bash
# Dates inside the repo
git log --format=fuller -10

# What GitHub sees
# → open your profile, hover the squares; future dates light up on arrival
```

## Notes and Caveats

- **Author date** is what the graph reads; **committer date** should be kept
  identical for consistency (that is why both variables are always set).
- Keep the timezone offset (`+07:00` for WIB) — a bare date can shift a commit
  to the previous day depending on how it is interpreted.
- Backdating is legitimate when it reflects work you actually did (e.g.
  importing or reconstructing history). It is visible to anyone who reads
  your profile — keep it honest.
- A later `git commit --amend` or rebase can silently rewrite dates. Re-check
  with `git log --format=fuller` after history surgery.

## Troubleshooting

**Wrong date already committed (not pushed yet):**

```bash
GIT_COMMITTER_DATE="2026-11-14T09:00:00+07:00" \
git commit --amend --no-edit --date="2026-11-14T09:00:00+07:00"
```

**Square not lighting up on GitHub:**

1. Commit is on a non-default branch → merge/push to `main`.
2. Author email differs from your verified email →
   `git config user.email` vs GitHub → Settings → Emails.
3. The repo is a fork → contributions only count on non-forks.
4. The date is in the future → expected; the square lights up on arrival.
5. Pushed less than a few minutes ago → GitHub needs a moment to recompute.

**Committed with the date still exported from an earlier batch:**

```bash
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
# then amend the affected unpushed commits as shown above
```

---

See also: [Semantic Commit Messages](readme.md#appendix) for the message
convention used in the examples above.
