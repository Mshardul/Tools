# Tools Collection Layout — Design

**Date:** 2026-08-21  
**Status:** Approved  
**Scope:** Turn this repository into a typed-bucket nursery for small personal tools. Individual tools graduate to their own repos when they outgrow the collection.

---

## Summary

This repo is a collection, not an application. Live tools live in type buckets. The root README is only a catalog. There is no shared runtime, lockfile, or “run everything” CI. A tool that becomes too large, too secret-heavy, or too user-facing leaves for its own repository.

---

## Layout

```
Tools/
  apps/                    # small web or desktop apps
  cli/                     # command-line tools
  extensions/
    chrome/
    vlc/
  archive/                 # superseded one-offs (not a live bucket)
  docs/                    # collection-level design notes only
  README.md                # catalog
```

Add a new top-level type only when a second example exists (Firefox, Raycast, etc.). Do not add `libs/` until two tools actually share code.

### Existing moves

| From | To |
|---|---|
| `claude-usage/` | `apps/claude-usage/` |
| `youtube-downloader/` | `cli/youtube-downloader/` |
| `archive/` | stays at repo root |

---

## Leaf contract

Anything not in `archive/` must have:

- A `kebab-case` directory name (stable for later GitHub URLs and graduation)
- `README.md` covering: what it is, how to install/run, one “not for” line
- Its own dependency file if it has dependencies
- No secrets and no machine-specific paths committed
- A row in the root catalog with status `active`, `graduated`, or `archived`

Optional only when needed: tests, per-tool `LICENSE`, screenshots, store-listing notes.

Collection-level design docs stay under `docs/`. Per-tool notes stay in the leaf.

---

## Catalog

Root `README.md` is a table: name (link), bucket, status, one-line purpose. Empty extension buckets may exist as placeholders (`extensions/chrome/`, `extensions/vlc/`) and are not catalog rows until they contain a tool.

---

## Graduation

Move a leaf to its own repo when any of these is true:

- it has users besides the author, or
- it needs its own CI, secrets, or releases, or
- working on it regularly distracts from the rest of the collection

How: new repo (copy or `git subtree split` / history filter). In this repo, replace the leaf with a short stub pointing at the new URL, or delete it and update the catalog to `graduated` with the new link. Do not use git submodules unless both repos are actively developed together.

---

## Non-goals

- Shared `package.json` / Python env at repo root
- A Netlify catalog site (individual web apps may still be deployed on their own later)
- Publishing Chrome Web Store / VLC addons as part of this layout change
- Rewriting historical specs under `docs/superpowers/` that still mention old paths

---

## Path note for `apps/claude-usage`

The dashboard currently fetches `/claude-usage/...` assuming the HTTP server is the repo root. After the move, fetches must be **relative to the tool directory** (`usage.db`, `projects/`) so the app works both when served from the leaf and when served from repo root at `/apps/claude-usage/`.
