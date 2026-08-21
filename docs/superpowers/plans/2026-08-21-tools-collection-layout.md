# Tools Collection Layout — Implementation Plan

> **For agentic workers:** Implement task-by-task. No git commits — user manages git manually.

**Goal:** Put live tools into typed buckets and make the root README a catalog that matches the approved spec.

**Architecture:** Mechanical directory moves plus path/docs updates. No shared runtime. Claude Usage fetch URLs become relative so the dashboard does not depend on the old `/claude-usage/` prefix.

**Tech Stack:** git mv, markdown, vanilla JS path strings

**Spec:** `docs/superpowers/specs/2026-08-21-tools-collection-design.md`

## Global Constraints

- Buckets: `apps/`, `cli/`, `extensions/chrome/`, `extensions/vlc/`, `archive/` at repo root
- Leaf names stay `kebab-case`
- No repo-root lockfile or shared CI
- No secrets in git
- Do not rewrite historical `2026-05-25-*` docs except if a link would 404 from the new README

## File Map

| File | Role |
|---|---|
| `apps/claude-usage/` | moved app |
| `cli/youtube-downloader/` | moved CLI |
| `extensions/chrome/`, `extensions/vlc/` | empty placeholders |
| `README.md` | catalog |
| `.gitignore` | ignore dashboard symlinks at new path |
| `apps/claude-usage/app.js` | relative data fetches |
| `apps/claude-usage/README.md` | setup paths |
| `cli/youtube-downloader/readme.md`, `pyproject.toml` | clone/homepage paths |

---

## Task 1: Directories

- [x] Create `apps/`, `cli/`, `extensions/chrome/`, `extensions/vlc/`
- [x] `git mv` `claude-usage` → `apps/claude-usage`
- [x] `git mv` `youtube-downloader` → `cli/youtube-downloader`
- [x] Add `.gitkeep` in empty extension dirs

**Verify:** `ls apps cli extensions/chrome extensions/vlc archive`

---

## Task 2: Claude Usage paths

- [x] Relative fetches in `app.js`
- [x] README setup + file tree

**Verify:** grep shows no `/claude-usage/` in `apps/claude-usage/` except historical wording if any

---

## Task 3: Catalog and ignore rules

- [x] Root README catalog (name, bucket, status, purpose)
- [x] `.gitignore` for `apps/claude-usage/usage.db` and `projects`
- [x] youtube-downloader homepage / clone paths

**Verify:** catalog links resolve; gitignore covers new symlink paths
