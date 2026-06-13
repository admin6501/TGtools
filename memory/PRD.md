# Bidar — Telegram Userbot (tg.sh)

## Overview
A single bash installer `tg.sh` that generates a Telethon-based Python userbot (`tools.py`)
and runs it via systemd (or nohup/foreground). Owner-only commands. AI via emergentintegrations
(Emergent LLM key). Persistent settings in `bot_config.json`.

## Architecture
- `tg.sh` = installer + manager (preflight deps, embedded Python heredoc, systemd setup, menu).
- `tools.py` = generated bot (Telethon handlers).
- `.env` = TG_API_ID/HASH/PHONE/ADMIN_USERS/EMERGENT_LLM_KEY.
- systemd service name: `tg-userbot`.

## Implemented (June 2026)
- Legacy commands kept unchanged: .keepalive/.stopalive, .startpish/.stoppish, .edit,
  .model, .persona, .setprompt, .cooldown, .st, .ocr, .tr, .help, .status.
- NEW v1.9.2 commands added (new command names only):
  .interval, .afk, .aigroups, .groupcd, .aireset, .r, .lang, .tl, .to,
  .img, .imgedit, .imgmodel (Nano Banana gemini-3.1-flash-image-preview),
  .search, .searchall, .sc/.music/.allow (yt-dlp + ffmpeg), .alive, .ping,
  .stats, .id, .botlang, .restart, .menu/.commands. Group handler for AI-in-groups
  + music link auto-detect. New settings persisted in bot_config.json.
- Manager menu added to tg.sh: Install / Start / Stop / Restart / Update / Status /
  Logs / Uninstall / Exit. Also non-interactive subcommands `tg.sh <action>`.
  Update = preflight (install missing deps) + regenerate tools.py + restart service
  (no re-entering credentials).

## Validation
- `bash -n tg.sh` OK; embedded Python `py_compile` OK; menu + CLI dispatch smoke-tested.
- NOT runtime-tested end-to-end (requires real Telegram credentials; cannot run in this env).

## Backlog / Next
- P1: `.sc` quality selection + send title/thumbnail as caption.
- P1: full bilingual coverage for legacy command messages via .botlang.
- P2: remote self-update of tg.sh from a URL (currently update regenerates from embedded source).
