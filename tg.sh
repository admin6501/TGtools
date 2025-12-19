#!/usr/bin/env bash
set -euo pipefail

PYTHON_FILE="tools.py"

log() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

is_termux() {
  [[ -n "${PREFIX:-}" && "${PREFIX:-}" == *"com.termux"* ]] || have pkg
}

SUDO=""
if [[ "${EUID:-$(id -u)}" -ne 0 ]] && have sudo; then
  SUDO="sudo"
fi

install_system_packages() {
  # Best-effort: install python3/pip + optional font/webp tools
  if is_termux; then
    log "Detected Termux. Installing packages via pkg..."
    pkg update -y || true
    pkg install -y python python-pip libwebp freetype fontconfig || true
    pkg install -y ttf-dejavu || true
    return 0
  fi

  if have apt-get; then
    log "Detected apt-get. Installing packages..."
    $SUDO apt-get update -y || true
    $SUDO apt-get install -y python3 python3-pip python3-venv || true
    $SUDO apt-get install -y fonts-dejavu-core webp || true
    $SUDO apt-get install -y libwebp-tools || true
    return 0
  fi

  if have dnf; then
    log "Detected dnf. Installing packages..."
    $SUDO dnf install -y python3 python3-pip || true
    $SUDO dnf install -y dejavu-sans-fonts libwebp-tools || true
    return 0
  fi

  if have yum; then
    log "Detected yum. Installing packages..."
    $SUDO yum install -y python3 python3-pip || true
    $SUDO yum install -y dejavu-sans-fonts libwebp-tools || true
    return 0
  fi

  if have pacman; then
    log "Detected pacman. Installing packages..."
    $SUDO pacman -Sy --noconfirm python python-pip || true
    $SUDO pacman -S --noconfirm ttf-dejavu libwebp || true
    return 0
  fi

  if have apk; then
    log "Detected apk. Installing packages..."
    $SUDO apk add --no-cache python3 py3-pip || true
    $SUDO apk add --no-cache ttf-dejavu libwebp-tools || true
    return 0
  fi

  if have zypper; then
    log "Detected zypper. Installing packages..."
    $SUDO zypper --non-interactive install python3 python3-pip || true
    $SUDO zypper --non-interactive install dejavu-fonts webp || true
    return 0
  fi

  warn "No supported package manager detected. Skipping system package installation."
  return 0
}

ensure_python_and_pip() {
  if ! have python3; then
    log "python3 not found. Attempting to install..."
    install_system_packages || true
  fi
  have python3 || die "python3 is still not available. Please install Python 3 manually."

  if ! python3 -m pip --version >/dev/null 2>&1; then
    log "pip is not available for python3. Attempting to install..."
    install_system_packages || true
  fi
  python3 -m pip --version >/dev/null 2>&1 || die "pip is still not available. Please install pip for Python 3."
}

pip_install() {
  local pkgs=("$@")
  python3 -m pip install --upgrade pip >/dev/null 2>&1 || true

  if python3 -m pip install "${pkgs[@]}"; then
    return 0
  fi

  warn "pip install failed (possibly permissions). Retrying with --user..."
  python3 -m pip install --user "${pkgs[@]}"
}

preflight() {
  log "Preflight: checking prerequisites..."
  install_system_packages || true
  ensure_python_and_pip
  log "Installing Python dependencies (telethon, pillow)..."
  pip_install telethon pillow || die "Failed to install required Python packages."
  log "Preflight complete."
}

# ---------- main ----------
preflight

read -r -p "Please enter your API ID: " api_id
read -r -p "Please enter your API Hash: " api_hash
read -r -p "Please enter your phone number: " phone_number
read -r -p "Please enter your channel username: " channel_username
read -r -p "Please enter admin user IDs (comma separated): " admin_users

export TG_API_ID="$api_id"
export TG_API_HASH="$api_hash"
export TG_PHONE_NUMBER="$phone_number"
export TG_CHANNEL_USERNAME="$channel_username"
export TG_ADMIN_USERS="$admin_users"

cat > "$PYTHON_FILE" <<'PY'
from telethon import TelegramClient, events, utils, errors
import asyncio
from datetime import datetime
import os
import tempfile
import textwrap
import shutil
import subprocess
from PIL import Image, ImageDraw, ImageFont
import json
import re
import random
import string

from telethon.tl.functions.messages import GetStickerSetRequest
from telethon.tl.functions.stickers import CreateStickerSetRequest, AddStickerToSetRequest
from telethon.tl.types import InputStickerSetShortName, InputStickerSetItem

def _env(name: str, required: bool = True) -> str:
    v = os.environ.get(name, "").strip()
    if required and not v:
        raise RuntimeError(f"Missing required env var: {name}")
    return v

api_id = _env("TG_API_ID")
api_hash = _env("TG_API_HASH")
phone_number = _env("TG_PHONE_NUMBER")
channel_username = _env("TG_CHANNEL_USERNAME")

admin_users_raw = _env("TG_ADMIN_USERS")
admin_users = [x.strip() for x in admin_users_raw.split(",") if x.strip()]

client = TelegramClient("session_name", api_id, api_hash)

keep_alive_active = False
auto_reply_active = False
default_reply = "صبور باشید در اسرع وقت پاسخگو هستم."
auto_reply_count = 0
last_auto_reply_time = None

# ---- Sticker pack state (per admin) ----
PACK_STATE_FILE = "sticker_packs.json"
_pack_state = None  # lazy-loaded

def _load_pack_state():
    global _pack_state
    if _pack_state is not None:
        return _pack_state
    try:
        with open(PACK_STATE_FILE, "r", encoding="utf-8") as f:
            _pack_state = json.load(f)
            if not isinstance(_pack_state, dict):
                _pack_state = {"packs": {}}
    except Exception:
        _pack_state = {"packs": {}}
    _pack_state.setdefault("packs", {})
    return _pack_state

def _save_pack_state():
    global _pack_state
    if _pack_state is None:
        return
    try:
        with open(PACK_STATE_FILE, "w", encoding="utf-8") as f:
            json.dump(_pack_state, f, ensure_ascii=False, indent=2)
    except Exception:
        pass

def _sanitize_short_name(s: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9_]", "_", s or "")
    s = re.sub(r"_+", "_", s).strip("_")
    return (s or "tgst").lower()

def _is_name_occupied(exc: Exception) -> bool:
    # سازگار با نسخه‌های مختلف Telethon:
    # - بعضی نسخه‌ها کلاس اختصاصی دارند
    # - بعضی نسخه‌ها فقط RPCError با متن STICKERSET_NAME_OCCUPIED می‌دهند
    name = exc.__class__.__name__
    text = str(exc) or ""
    if name == "StickersetNameOccupiedError":
        return True
    if "STICKERSET_NAME_OCCUPIED" in text:
        return True
    if "name occupied" in text.lower():
        return True
    return False

async def _pack_exists(short_name: str) -> bool:
    try:
        await client(GetStickerSetRequest(stickerset=InputStickerSetShortName(short_name), hash=0))
        return True
    except Exception:
        return False

async def _get_or_create_pack_for_admin(admin_id: int, first_doc, emoji: str = "📝") -> str:
    state = _load_pack_state()
    packs = state.get("packs", {})
    admin_key = str(admin_id)

    pack_info = packs.get(admin_key) or {}
    short_name = pack_info.get("short_name")
    if short_name and await _pack_exists(short_name):
        return short_name

    try:
        sender = await client.get_entity(admin_id)
        sender_name = (getattr(sender, "first_name", None) or getattr(sender, "title", None) or "Admin").strip()
    except Exception:
        sender_name = "Admin"

    me = await client.get_me()
    base = getattr(me, "username", None) or f"user{me.id}"
    title = f"{sender_name} • Text Stickers"
    title = title[:64]

    base_short = _sanitize_short_name(f"tgst_{admin_id}_{base}")
    base_short = base_short[:50]

    owner = await client.get_input_entity("me")
    item = InputStickerSetItem(document=utils.get_input_document(first_doc), emoji=emoji)

    for _ in range(12):
        suffix = "".join(random.choices(string.ascii_lowercase + string.digits, k=6))
        candidate = (base_short if base_short else "tgst") + "_" + suffix
        candidate = candidate[:64]

        try:
            await client(CreateStickerSetRequest(
                user_id=owner,
                title=title,
                short_name=candidate,
                stickers=[item],
            ))
            packs[admin_key] = {"short_name": candidate, "title": title}
            state["packs"] = packs
            _save_pack_state()
            return candidate

        except errors.RPCError as e:
            if _is_name_occupied(e):
                continue
            raise
        except Exception:
            raise

    raise RuntimeError("Could not allocate a unique sticker pack short_name after multiple attempts.")

async def _add_sticker_to_admin_pack(admin_id: int, doc, emoji: str = "📝") -> str:
    state = _load_pack_state()
    packs = state.get("packs", {})
    admin_key = str(admin_id)

    short_name = (packs.get(admin_key) or {}).get("short_name")
    if not short_name or not await _pack_exists(short_name):
        short_name = await _get_or_create_pack_for_admin(admin_id, doc, emoji=emoji)
        return short_name

    item = InputStickerSetItem(document=utils.get_input_document(doc), emoji=emoji)
    await client(AddStickerToSetRequest(
        stickerset=InputStickerSetShortName(short_name),
        sticker=item,
    ))
    return short_name

def is_admin(user_id):
    return str(user_id) in admin_users

def is_bot(user):
    return user.bot

async def keep_alive():
    global keep_alive_active
    while keep_alive_active:
        await client.send_message(channel_username, "Keeping the channel active")
        await asyncio.sleep(5)

@client.on(events.NewMessage(pattern=r"\.keepalive"))
async def start_keep_alive(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return
    global keep_alive_active
    if not keep_alive_active:
        keep_alive_active = True
        await event.reply("Keepalive started!")
        asyncio.create_task(keep_alive())
    else:
        await event.reply("Keepalive is already active.")

@client.on(events.NewMessage(pattern=r"\.stopalive"))
async def stop_keep_alive(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return
    global keep_alive_active
    if keep_alive_active:
        keep_alive_active = False
        await event.reply("Keepalive stopped!")
    else:
        await event.reply("Keepalive is not active.")

@client.on(events.NewMessage(pattern=r"\.startpish"))
async def start_auto_reply(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return
    global auto_reply_active
    if not auto_reply_active:
        auto_reply_active = True
        await event.reply("Auto-reply started!")
    else:
        await event.reply("Auto-reply is already active.")

@client.on(events.NewMessage(pattern=r"\.stoppish"))
async def stop_auto_reply(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return
    global auto_reply_active
    if auto_reply_active:
        auto_reply_active = False
        await event.reply("Auto-reply stopped!")
    else:
        await event.reply("Auto-reply is not active.")

@client.on(events.NewMessage(pattern=r"\.edit (.+)"))
async def edit_auto_reply(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return
    global default_reply
    default_reply = event.pattern_match.group(1)
    await event.reply(f"Auto-reply message updated to: {default_reply}")

@client.on(events.NewMessage(pattern=r"\.st(?!\w)"))
async def text_to_sticker(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return

    if (event.raw_text or "").strip() != ".st":
        return

    if not event.is_reply:
        await event.reply("Please reply to a user's text message, then send .st")
        return

    reply = await event.get_reply_message()
    if not reply or not (reply.raw_text or "").strip():
        await event.reply("Replied message has no text to convert.")
        return

    text_to_render = (reply.raw_text or "").strip()

    size = 512
    margin = 30
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    font_size = 52
    font = None
    font_candidates = [
        "DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/data/data/com.termux/files/usr/share/fonts/TTF/DejaVuSans.ttf",
        "arial.ttf",
    ]
    for fp in font_candidates:
        try:
            font = ImageFont.truetype(fp, font_size)
            break
        except Exception:
            font = None
    if font is None:
        font = ImageFont.load_default()

    def wrap_lines(txt, fnt, max_width):
        lines = []
        for para in txt.splitlines() or [""]:
            para = para.strip()
            if not para:
                lines.append("")
                continue
            tmp = textwrap.wrap(para, width=24) or [para]
            lines.extend(tmp)
        return lines[:20]

    def text_bbox(multiline, fnt):
        if hasattr(draw, "multiline_textbbox"):
            bbox = draw.multiline_textbbox((0, 0), multiline, font=fnt, spacing=8, align="center")
            return (bbox[2] - bbox[0]), (bbox[3] - bbox[1])
        w, h = draw.multiline_textsize(multiline, font=fnt, spacing=8)
        return w, h

    max_w = size - 2 * margin
    max_h = size - 2 * margin

    for fs in range(font_size, 18, -2):
        fnt = None
        for fp in font_candidates:
            try:
                fnt = ImageFont.truetype(fp, fs)
                break
            except Exception:
                fnt = None
        if fnt is None:
            fnt = ImageFont.load_default()

        lines = wrap_lines(text_to_render, fnt, max_w)
        multiline = "\n".join(lines)
        w, h = text_bbox(multiline, fnt)
        if w <= max_w and h <= max_h:
            font = fnt
            break

    lines = wrap_lines(text_to_render, font, max_w)
    multiline = "\n".join(lines)
    w, h = text_bbox(multiline, font)
    x = (size - w) // 2
    y = (size - h) // 2

    draw.multiline_text(
        (x, y),
        multiline,
        font=font,
        fill=(255, 255, 255, 255),
        spacing=8,
        align="center",
        stroke_width=2,
        stroke_fill=(0, 0, 0, 200),
    )

    tmpdir = tempfile.gettempdir()
    webp_path = os.path.join(tmpdir, f"st_{event.id}_{reply.id}.webp")
    png_path = os.path.join(tmpdir, f"st_{event.id}_{reply.id}.png")

    try:
        try:
            img.save(webp_path, format="WEBP", lossless=True, quality=95, method=6)
            out_path = webp_path
        except Exception:
            img.save(png_path, format="PNG")
            out_path = png_path
            if shutil.which("cwebp"):
                try:
                    subprocess.run(["cwebp", "-q", "90", png_path, "-o", webp_path], check=True)
                    out_path = webp_path
                except Exception:
                    out_path = png_path

        sent = await client.send_file(event.chat_id, out_path, reply_to=reply.id, force_document=False)

        # Add generated sticker to admin pack (silent)
        sent_msg = sent[0] if isinstance(sent, (list, tuple)) and sent else sent
        doc = getattr(sent_msg, "document", None)
        if doc is None and getattr(sent_msg, "media", None) is not None:
            doc = getattr(sent_msg.media, "document", None)
        if doc is not None:
            try:
                await _add_sticker_to_admin_pack(event.sender_id, doc, emoji="📝")
            except Exception:
                pass

        try:
            await event.delete()
        except Exception:
            pass
    finally:
        for fp in (webp_path, png_path):
            try:
                if os.path.exists(fp):
                    os.remove(fp)
            except Exception:
                pass

@client.on(events.NewMessage(pattern=r"\.help"))
async def show_help(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return
    help_message = (
        "**Available Commands:**\n"
        ".keepalive - Start keepalive messages.\n"
        ".stopalive - Stop keepalive messages.\n"
        ".startpish - Start auto-reply.\n"
        ".stoppish - Stop auto-reply.\n"
        ".edit <message> - Edit auto-reply message.\n"
        ".st - Convert replied text to sticker.\n"
        ".status - Show bot status.\n"
    )
    await event.reply(help_message)

@client.on(events.NewMessage(incoming=True))
async def auto_reply(event):
    global auto_reply_active, default_reply, auto_reply_count, last_auto_reply_time
    sender = await event.get_sender()
    if auto_reply_active and event.is_private and not is_bot(sender):
        await event.reply(default_reply)
        auto_reply_count += 1
        last_auto_reply_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

@client.on(events.NewMessage(pattern=r"\.status"))
async def status(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return
    status_message = (
        f"**Bot Status:**\n"
        f"Auto-reply: {'Active' if auto_reply_active else 'Inactive'}\n"
        f"Keepalive: {'Active' if keep_alive_active else 'Inactive'}\n"
        f"Auto-reply count: {auto_reply_count}\n"
        f"Last auto-reply time: {last_auto_reply_time if last_auto_reply_time else 'No replies yet'}"
    )
    await event.reply(status_message)

async def main():
    await client.start(phone=phone_number)
    print("Client Created and Online")
    await client.run_until_disconnected()

client.loop.run_until_complete(main())
PY

log "Python file '${PYTHON_FILE}' has been created."
python3 "$PYTHON_FILE"
