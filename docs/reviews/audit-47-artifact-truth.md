# Audit-47 — shipped-artifact truth (S94)

Not a cold lens — an evidence stage. audit-45 edited export_presets.cfg but
the dist/ builds it "certified" were 7 commits stale (build `ad63d84`) and no
exported binary had ever been launched. This stage rebuilt and booted them.

## Found + fixed

- **Web export could not build at all.** The preset shipped
  `vram_texture_compression/for_desktop|for_mobile=true` — S3TC/BPTC/ETC2
  variant export fails validation on this toolchain and produced an EMPTY
  configuration-error list (no diagnostic text). Both disabled — also the
  right call for pixel art (compressed variants are wasted bytes).
  Web zip: 16M → 12M.
- **Blender-importer noise on every export scan** — `.blend/.fbx/.obj`
  sources in `tools/art/src/` are pipeline inputs, not game resources, but
  Godot scanned them anyway. `tools/art/src/.gdignore` ends it; Python rig
  pipeline is unaffected (it never loads through Godot).
- **PWA COI contradiction** — `thread_support=false` (audit-45) while
  `progressive_web_app/ensure_cross_origin_isolation_headers=true` was left
  set; flipped off, and PWA disabled outright (less surface to validate).
- **Stale dist** — rebuilt windows+web at HEAD (`09cab25`),
  `dist/build.txt` ties bytes to commit.

## Verified evidence

- `tools/package.sh windows|web` both green; SHA256SUMS emitted.
- Web PCK contents: `strings index.pck` → 0 hits for
  `res://(docs|tools|prototype|store)/`; all `assets/kin` sprites present.
- Web build served (`python3 -m http.server`) and opened in a live browser
  preview — the export actually boots, not just zips.
- Smoke: 962–965 checks, 0 failures across 3 runs (one transient flake
  observed mid-verification, same seed-conditional class noted in S90).

## Deferred

- Windows `.exe` can't execute on macOS — PCK verified, not booted.
- Android debug APK build needs SDK; debug template exists, release
  keystore remains an owner item.
