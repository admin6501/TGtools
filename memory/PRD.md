# Telegram Userbot (tg.sh) — PRD

## Problem Statement (original, Persian)
کاربر یک اسکریپت یوزربات تلگرام (Telethon) دارد. درخواست‌ها:
1. آنلاین نگه‌داشتن اکانت بدون ارسال پیام به کانال.
2. پاسخگویی خودکار (اتوریپلای) با هوش مصنوعی Emergent.

## User Choices
- همه مدل‌های Emergent در دسترس باشند و از داخل تلگرام با دستور قابل تغییر.
- اتوریپلای فقط در چت خصوصی (PV).
- چند شخصیت/لحن آماده + قابل تنظیم از داخل تلگرام.
- آنلاین‌نگه‌داری با آپدیت وضعیت آنلاین (بدون پیام).
- اسکریپت نصب، کلید Emergent را از کاربر بپرسد.

## Architecture
- Single bash installer `tg.sh` that generates `tools.py` (Telethon userbot) at runtime.
- AI via `emergentintegrations` (LlmChat) — providers: openai / anthropic / gemini.
- Per-user multi-turn AI session keyed by sender_id.

## What's Implemented (2026-06-09)
- Installer now installs `emergentintegrations` (custom index) + `python-dotenv`; prompts for Emergent LLM key (TG_EMERGENT_LLM_KEY). Channel prompt removed.
- `keep_alive()` now refreshes Telegram online status via `UpdateStatusRequest(offline=False)` every 60s — no channel messages.
- AI auto-reply in private chats using LlmChat; falls back to default message if AI/key unavailable.
- Telegram commands:
  - `.model` / `.model <provider> <model>` — view/switch AI model (whitelisted).
  - `.persona` / `.persona <key>` — formal / friendly / professional / witty.
  - `.setprompt <text>` — custom system prompt (sets persona=custom).
  - existing: `.keepalive .stopalive .startpish .stoppish .edit .st .help .status`.
- `.help` and `.status` updated (status shows model, persona, AI availability).

## Validation
- `bash -n tg.sh` OK. Generated Python `py_compile` OK. `send_message -> str` confirmed.
- Live Telegram run is user-side (needs real API ID/HASH/phone session).

## Backlog / Next
- P1: `.model`/`.persona` persistence across restarts (save to JSON state file).
- P2: Optional group auto-reply (on mention) — currently PV only by design.
- P2: Rate limiting / cooldown per user for auto-reply.
