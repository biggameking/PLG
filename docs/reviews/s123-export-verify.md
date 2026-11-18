# S123 — 1.0.0 release-candidate verification + first-session captures

**Scope:** the product had never been re-exported at 1.0.0, and the first-session
hint card had never been reviewed as rendered output.

## Found

| # | Sev | Finding |
|---|-----|---------|
| 1 | MED | **Exported pcks ship no raw `.ttf`** — the font importer keeps only the imported fontdata; `hud.gd`'s `load_dynamic_font` reads the raw path, which is absent in the pck. First real pck boot (web index.pck via `--main-pack`) showed both fallback fonts `Can't open` → zh + HUD glyphs would tofu on web/Android. Editor/headless runs masked it (raw files on disk). |
| 2 | LOW | zh.csv survived — `importer="keep"` stores raw bytes at path; `FileAccess` works in the pck. Verified by absence of csv errors in the pck boot. |
| 3 | LOW | First-session hint card clipped mid-word (`LMB swings — fre`, `B builds — your`) — truncation dropped the actual instruction the hint exists to teach. |

## Fixed

- `hud.gd`: fallback chain built via `load()` (walks the .import remap) instead of `load_dynamic_font`. Comment corrected — sidecars ARE the export path.
- `_wrap_font(txt, w, size, max_lines)`: greedy word-wrap for the hint column — word boundaries, indented continuations, word-clip + `…` on real overflow. Hints get 4 rows (carries the whole kinbox recipe); mission row keeps its single-line contract. audit-76 follow-up: spaceless CJK tokens pre-split at glyph boundaries (zh hints no longer bleed off the screen edge), and the last-line clip falls back to glyph-clip when no word boundary exists past the indent.
- `tools/shot_firstmin.gd`: windowed capture of title/spawn/hint/guide — the first-session evidence loop.

## Verification

- `tools/package.sh all` → `kinbound-1.0.0-{windows,web,debug.apk}` + SHA256SUMS, zero export warnings
- web `index.pck` booted via `--main-pack --quit-after 600`: **zero errors** (was 2 font errors)
- Windows artifact: 39MB zip containing the 118MB embedded-pck exe (standard release shape; same export run)
- smoke **1055/0/0skip** — new pins: 3 font import-remap resolves, wrap column-fit/indent/ellipsis
- Evidence: `s123-{title,spawn,hint,guide}.png` — wrapped hint card renders continuations indented + ellipsized

## Process note

The font bug survived every smoke run because the check asserted glyph coverage
`has_char` — true in-editor where raw .ttf resolves regardless of load path. The
new pins assert `ResourceLoader.exists` + `load() is FontFile` — the condition
the export actually depends on.
