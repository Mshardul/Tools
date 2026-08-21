# Prompt: Pick and build Tools nursery mini-tools

Use this in a new agent chat for the [Tools](../README.md) collection.  
**Default behavior:** first propose **groups of mini-tools** ranked by **effort vs usability/usefulness**, wait for the user to pick a group (or specific ids), **then** implement. Do not start coding before the user chooses.

Copy everything below the line into the chat.

---

## Task

1. Read the current backlog and repo state.
2. Propose **build batches** ranked by **effort vs usability/usefulness** (not “quick wins” alone).
3. After the user picks a group (e.g. “A”) or explicit ids (`T-022 T-024`), implement those leaves.

Read and follow:

- [`BACKLOG.md`](../BACKLOG.md) — leaf rules, status, priority; skip `active`, `dropped`, `graduated`
- [`README.md`](../README.md)
- [`docs/superpowers/specs/2026-08-21-tools-collection-design.md`](../docs/superpowers/specs/2026-08-21-tools-collection-design.md)
- Reference implementations: `cli/id-gen`, `cli/password-gen`, `cli/port-tool`, `cli/pb`, `cli/trash`, `cli/notify`

Do **not** invent new backlog rows unless asked. Do **not** merge unrelated tools into one binary.

If the user already names ids/slugs in the first message, skip the menu and go straight to **Build process**.

---

## Step 1 — Propose groups (mandatory unless ids given)

Scan `BACKLOG.md` for rows with status `idea` or `next` (and `building` only if clearly unfinished).

Score each candidate on two axes (use backlog `effort` plus your judgment of real-world usefulness):

| Axis | Low | High |
|---|---|---|
| **Effort** | hours, stdlib Python CLI, few edge cases | days+, OS permissions, GUI, flaky APIs |
| **Usability / usefulness** | rare niche, novelty only | frequent friction, many users-including-you, fits future macOS launcher |

**Rank by leverage:** prefer **high usefulness per unit effort** (useful ÷ effort).  
A medium-effort tool that you would use daily can outrank a trivial tool nobody needs.  
A low-effort toy with weak usefulness does **not** get Tier A just because it is easy.

Also prefer leaves a future macOS host can call via subprocess/import. Deprioritize already `active` rows and permission-heavy giants unless usefulness clearly justifies them.

Propose **2–4 groups**:

**Output format (use this shape):**

### Tier A — best usefulness-per-effort

**Why pick this group:** 2–4 sentences — who it helps, what friction it removes, why the effort is justified now vs later. Be concrete (not “these are good tools”).

| id | Tool | Effort | Usefulness | Why this ratio |
|---|---|---|---|---|
| T-… | `slug` | low/med | high/med | one short reason |

### Tier B — still good ratio, or higher effort for clear payoff

**Why pick this group:** 2–4 sentences — when A is wrong (e.g. you already have those habits covered) and why this batch’s tradeoff is still worth it.

| id | Tool | Effort | Usefulness | Why |
|---|---|---|---|---|
| T-… | `slug` | … | … | … |

### Tier C / later — weak ratio or blocked

**Why pick this group (only if…):** 1–3 sentences — when it makes sense (e.g. you explicitly want Mac UI surface area, or a permission-heavy fight). Otherwise say why to skip for now.

| id | Tool | Note |
|---|---|---|
| T-… | `slug` | low usefulness, or effort too high for now |

### Suggested batch to build next

1. …  
2. …  
3. …  

**Why this suggestion over the other tiers:** 1–2 sentences.

End with **one question**: which group (A / B / custom ids)?  

**STOP. Do not implement until the user answers.**

Group size: about **4–8 tools** for Tier A (a coherent batch), not the entire backlog. Keep each tool its own leaf (no mega-utils). Every tier heading **must** include its **Why pick this group** blurb before the table.

---

## Step 2 — Build process (after the user picks)

For each selected id:

1. Set row to `building` in `BACKLOG.md` (at most two `P1`s repo-wide).
2. Confirm `bucket/slug/` exists; flesh out README.
3. **TDD** for pure logic: failing tests → implement → pass.
4. CLI with `argparse`, `-h`, stderr errors prefixed with `slug:`.
5. Update `ticket-backlog.md` (`T-XXX-1`, …).
6. Smoke-test happy path (macOS glue where relevant).
7. Set `active`; add root README catalog row.
8. **No git commit** unless the user asks.

Batch the picked group in one session when practical; still **one directory per tool**.

---

## Product shape (important)

1. **Python preferred** (`python3`, stdlib first; pin leaf deps only when needed).
2. **One leaf directory per mini-tool** at `bucket/slug/` with README, `*.py` entrypoint, tests when useful, optional `config.sample.yaml`, `ticket-backlog.md` when building+.
3. **Tiny related conversions** = one leaf with `--from` / `--to` or mode flags.
4. Layout: `cli/` primary; `apps/` when needed; `extensions/chrome|vlc|macos/` for platform shells.
5. **Future macOS launcher** (Raycast / Spotlight / Alfred–like) will **invoke** these mini-tools, not rewrite them:
   - Callable without a TTY UI: argv, stdin/stdout, exit codes; optional `--json` when structured output helps a GUI.
   - Logic in importable functions; `main()` thin.
   - No GUI frameworks inside `cli/` leaves.
6. **macOS permissions:** avoid Accessibility / Finder / Input Monitoring unless the row requires them. Prefer YAML config + CLI overrides (see `cli/trash`: default no Finder).
7. **Publish:** MIT, free via this GitHub repo.

---

## CLI conventions

- Document: `python3 <module>.py …` from the leaf dir.
- Exit `0` on success; non-zero on errors.
- Clipboard copy opt-in (`-c`), never required.
- Config: `~/.config/tools/<slug>.yaml` or `TOOLS_<SLUG>_CONFIG` / `--config`; CLI overrides file.
- No telemetry. No secrets in the repo.

---

## Out of scope unless the backlog row says so

- Mega “utils” binary
- Building the full macOS launcher app now
- Chrome Web Store / Mac App Store submission

---

## Done when (per built tool)

- [ ] Tests pass (if any)
- [ ] README: usage + “not for”
- [ ] `ticket-backlog.md` updated
- [ ] `BACKLOG.md` → `active`
- [ ] Root README catalog updated
- [ ] Leaf importable / subprocess-friendly for a future macOS host UI
