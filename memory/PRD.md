# PRD - tg.sh Telegram Bot Script

## Original Problem Statement
رفع باگ‌های اسکریپت tg.sh (ربات تلگرام)

## Architecture
- Single bash script (`tg.sh`) that:
  1. Installs system dependencies (python, pip, fonts, webp tools)
  2. Installs Python packages (telethon, pillow)
  3. Downloads Vazirmatn Persian font
  4. Generates a `tools.py` Python file (Telegram userbot)
  5. Runs the Python userbot

## Core Features
- Keepalive: sends periodic messages to a channel
- Auto-reply: automatic response to private messages
- Text-to-sticker: converts replied text to premium styled WebP stickers
- Sticker pack management: auto-creates/adds to personal sticker packs

## What's Been Implemented (Jan 2026)
- [x] Restored complete Python heredoc code (was replaced with placeholder)
- [x] Fixed api_id int conversion for TelegramClient
- [x] Fixed is_bot() null safety
- [x] Added Vazirmatn font to Python font_candidates
- [x] Fixed event handler ordering (admin commands before auto_reply)

## Backlog
- P1: Add `.font` command for theme selection
- P2: Add rate limiting to auto-reply
- P2: Add `.stats` command for detailed usage analytics
