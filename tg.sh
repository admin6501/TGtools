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
  # Best-effort system deps: python3/pip + fonts + webp tools
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
    $SUDO apt-get install -y fonts-dejavu-core || true
    $SUDO apt-get install -y libwebp-tools webp || true
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
import json
import re
import random
import string
import hashlib
import math

from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

from telethon.tl.functions.messages import GetStickerSetRequest
from telethon.tl.functions.stickers import CreateStickerSetRequest, AddStickerToSetRequest
from telethon.tl.types import InputStickerSetShortName, InputStickerSetItem


def _env(name: str, required: bool = True) -> str:
    v = os.environ.get(name, "").strip()
    if required and not v:
        raise RuntimeError(f"Missing required env var: {name}")
    return v


api_id = int(_env("TG_API_ID"))
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

# ---- state ----
STATE_FILE = "sticker_state.json"
_state = None

SEEN_LIMIT_PER_ADMIN = 2000

def _load_state():
    global _state
    if _state is not None:
        return _state
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            _state = json.load(f)
            if not isinstance(_state, dict):
                _state = {"packs": {}}
    except Exception:
        _state = {"packs": {}}
    _state.setdefault("packs", {})
    return _state

def _save_state():
    global _state
    if _state is None:
        return
    try:
        with open(STATE_FILE, "w", encoding="utf-8") as f:
            json.dump(_state, f, ensure_ascii=False, indent=2)
    except Exception:
        pass

def _sanitize_short_name(s: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9_]", "_", s or "")
    s = re.sub(r"_+", "_", s).strip("_")
    return (s or "tgst").lower()

def _is_name_occupied(exc: Exception) -> bool:
    # نسخه‌-سازگار؛ بدون import مستقیم StickersetNameOccupiedError
    name = exc.__class__.__name__
    txt = str(exc) or ""
    if name == "StickersetNameOccupiedError":
        return True
    if "STICKERSET_NAME_OCCUPIED" in txt:
        return True
    if "name occupied" in txt.lower():
        return True
    return False

async def _pack_exists(short_name: str) -> bool:
    try:
        await client(GetStickerSetRequest(stickerset=InputStickerSetShortName(short_name), hash=0))
        return True
    except Exception:
        return False

def _get_admin_info(admin_id: int) -> dict:
    st = _load_state()
    packs = st.get("packs", {})
    info = packs.get(str(admin_id)) or {}
    info.setdefault("seen", [])
    info.setdefault("sent_pack_to_saved", False)
    info.setdefault("short_name", None)
    info.setdefault("title", None)
    return info

def _set_admin_info(admin_id: int, info: dict):
    st = _load_state()
    st.setdefault("packs", {})
    st["packs"][str(admin_id)] = info
    _save_state()

def _seen_key(chat_id: int, reply_id: int) -> str:
    return f"{chat_id}:{reply_id}"

def _already_added_to_pack(admin_id: int, chat_id: int, reply_id: int) -> bool:
    info = _get_admin_info(admin_id)
    return _seen_key(chat_id, reply_id) in set(info.get("seen") or [])

def _mark_added_to_pack(admin_id: int, chat_id: int, reply_id: int):
    info = _get_admin_info(admin_id)
    seen = info.get("seen") or []
    key = _seen_key(chat_id, reply_id)
    if key in set(seen):
        return
    seen.append(key)
    if len(seen) > SEEN_LIMIT_PER_ADMIN:
        seen = seen[-SEEN_LIMIT_PER_ADMIN:]
    info["seen"] = seen
    _set_admin_info(admin_id, info)

async def _maybe_send_pack_preview_to_saved(admin_id: int, local_sticker_path: str):
    # «خود پک» بدون لینک: ارسال یک استیکر به Saved Messages یک‌بار
    info = _get_admin_info(admin_id)
    if info.get("sent_pack_to_saved", False):
        return
    if not info.get("short_name"):
        return
    try:
        await client.send_file("me", local_sticker_path)
        info["sent_pack_to_saved"] = True
        _set_admin_info(admin_id, info)
    except Exception:
        # silent
        pass

async def _get_or_create_pack_for_admin(admin_id: int, first_doc, emoji: str = "📝") -> str:
    info = _get_admin_info(admin_id)
    short_name = info.get("short_name")
    if short_name and await _pack_exists(short_name):
        return short_name

    try:
        ent = await client.get_entity(admin_id)
        sender_name = (getattr(ent, "first_name", None) or getattr(ent, "title", None) or "Admin").strip()
    except Exception:
        sender_name = "Admin"

    me = await client.get_me()
    base = getattr(me, "username", None) or f"user{me.id}"

    title = (f"{sender_name} • Premium Text Stickers")[:64]
    base_short = _sanitize_short_name(f"tgst_{admin_id}_{base}")[:50]

    owner = await client.get_input_entity("me")
    item = InputStickerSetItem(document=utils.get_input_document(first_doc), emoji=emoji)

    for _ in range(18):
        suffix = "".join(random.choices(string.ascii_lowercase + string.digits, k=6))
        candidate = ((base_short if base_short else "tgst") + "_" + suffix)[:64]
        try:
            await client(CreateStickerSetRequest(
                user_id=owner,
                title=title,
                short_name=candidate,
                stickers=[item],
            ))
            info["short_name"] = candidate
            info["title"] = title
            # sent_pack_to_saved را اینجا true نمی‌کنیم؛ داخل .st با فایل واقعی می‌فرستیم
            _set_admin_info(admin_id, info)
            return candidate

        except errors.RPCError as e:
            if _is_name_occupied(e):
                continue
            raise

    raise RuntimeError("Could not allocate a unique sticker pack short_name after multiple attempts.")

async def _add_sticker_to_admin_pack(admin_id: int, doc, emoji: str = "📝") -> str:
    info = _get_admin_info(admin_id)
    short_name = info.get("short_name")
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
    return bool(getattr(user, "bot", False))

# ---------- Premium Sticker Renderer ----------
def _seeded_rng(text: str) -> random.Random:
    h = hashlib.sha256(text.encode("utf-8")).hexdigest()
    seed = int(h[:16], 16)
    return random.Random(seed)

def _lerp(a, b, t: float):
    return int(a + (b - a) * t)

def _mesh_gradient(size: int, cA, cB, cC, cD):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    px = img.load()
    for y in range(size):
        ty = y / (size - 1)
        for x in range(size):
            tx = x / (size - 1)
            r1 = _lerp(cA[0], cB[0], tx); g1 = _lerp(cA[1], cB[1], tx); b1 = _lerp(cA[2], cB[2], tx)
            r2 = _lerp(cC[0], cD[0], tx); g2 = _lerp(cC[1], cD[1], tx); b2 = _lerp(cC[2], cD[2], tx)
            r = _lerp(r1, r2, ty); g = _lerp(g1, g2, ty); b = _lerp(b1, b2, ty)
            px[x, y] = (r, g, b, 255)
    return img

def _soft_noise(base: Image.Image, rng: random.Random, amount: int = 7):
    w, h = base.size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    p = layer.load()
    for y in range(h):
        for x in range(w):
            v = rng.randint(-amount, amount)
            a = rng.randint(10, 22)
            p[x, y] = (v & 255, v & 255, v & 255, a)
    return Image.alpha_composite(base, layer)

def _bokeh(base: Image.Image, rng: random.Random, n: int = 9):
    w, h = base.size
    layer = Image.new("RGBA", (w, h), (0,0,0,0))
    d = ImageDraw.Draw(layer)
    for _ in range(n):
        r = rng.randint(40, 120)
        x = rng.randint(-20, w+20)
        y = rng.randint(-20, h+20)
        col = (255, 255, 255, rng.randint(12, 35))
        d.ellipse((x-r, y-r, x+r, y+r), fill=col)
    layer = layer.filter(ImageFilter.GaussianBlur(radius=14))
    return Image.alpha_composite(base, layer)

def _accent_sweep(base: Image.Image, accent_rgb):
    size = base.size[0]
    layer = Image.new("RGBA", (size, size), (0,0,0,0))
    d = ImageDraw.Draw(layer)
    # یک نوار مورب ثابت (کم، شیک)
    d.polygon([(int(size*0.15), 0), (int(size*0.55), 0), (int(size*0.35), size), (int(size*-0.05), size)],
              fill=(accent_rgb[0], accent_rgb[1], accent_rgb[2], 22))
    layer = layer.filter(ImageFilter.GaussianBlur(radius=22))
    return Image.alpha_composite(base, layer)

def _fit_font(draw: ImageDraw.ImageDraw, text: str, font_candidates: list, max_w: int, max_h: int, start: int = 66, min_size: int = 20):
    def bbox(multiline: str, fnt):
        if hasattr(draw, "multiline_textbbox"):
            b = draw.multiline_textbbox((0, 0), multiline, font=fnt, spacing=10, align="center")
            return (b[2]-b[0]), (b[3]-b[1])
        return draw.multiline_textsize(multiline, font=fnt, spacing=10)

    def wrap(txt: str, width_chars: int):
        lines = []
        for para in (txt or "").splitlines() or [""]:
            para = para.strip()
            if not para:
                lines.append("")
                continue
            lines.extend(textwrap.wrap(para, width=width_chars) or [para])
        return lines[:14]

    for fs in range(start, min_size-1, -2):
        fnt = None
        for fp in font_candidates:
            try:
                fnt = ImageFont.truetype(fp, fs)
                break
            except Exception:
                fnt = None
        if fnt is None:
            fnt = ImageFont.load_default()

        width_chars = max(14, min(34, max_w // max(10, fs)))
        ml = "\n".join(wrap(text, width_chars))
        w, h = bbox(ml, fnt)
        if w <= max_w and h <= max_h:
            return fnt, ml

    fnt = ImageFont.load_default()
    return fnt, "\n".join((textwrap.wrap(text, width=24) or [text])[:14])

def build_premium_text_sticker(text: str, size: int = 512) -> Image.Image:
    rng = _seeded_rng(text)

    themes = [
        ((10, 16, 28), (20, 30, 48), (18, 80, 120), (40, 170, 200), (60, 220, 210)),
        ((16, 16, 18), (28, 22, 40), (70, 40, 140), (140, 80, 255), (220, 210, 255)),
        ((12, 12, 12), (28, 28, 28), (120, 90, 20), (220, 180, 80), (255, 245, 210)),
        ((12, 10, 20), (22, 18, 40), (160, 30, 120), (255, 80, 180), (255, 230, 245)),
    ]
    cA, cB, cC, cD, accent = rng.choice(themes)

    bg = _mesh_gradient(size, cA, cB, cC, cD)
    bg = _soft_noise(bg, rng, amount=7)
    bg = _bokeh(bg, rng, n=rng.randint(7, 10))
    bg = _accent_sweep(bg, accent_rgb=accent)

    # glass card
    card = Image.new("RGBA", (size, size), (0,0,0,0))
    cd = ImageDraw.Draw(card)

    pad = 44
    card_w = size - 2*pad
    card_h = int(size * 0.56)
    x0 = pad
    y0 = (size - card_h)//2
    x1 = x0 + card_w
    y1 = y0 + card_h

    shadow = Image.new("RGBA", (size, size), (0,0,0,0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((x0+6, y0+12, x1+6, y1+12), radius=56, fill=(0,0,0,110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=16))
    bg = Image.alpha_composite(bg, shadow)

    cd.rounded_rectangle((x0, y0, x1, y1), radius=56, fill=(12, 14, 18, 150), outline=(255,255,255,70), width=2)

    ring = Image.new("RGBA", (size, size), (0,0,0,0))
    rd = ImageDraw.Draw(ring)
    rd.rounded_rectangle((x0+10, y0+10, x1-10, y1-10), radius=48, outline=(accent[0], accent[1], accent[2], 90), width=3)
    ring = ring.filter(ImageFilter.GaussianBlur(radius=0.6))
    card = Image.alpha_composite(card, ring)

    bg = Image.alpha_composite(bg, card)

    # text
    overlay = Image.new("RGBA", (size, size), (0,0,0,0))
    d = ImageDraw.Draw(overlay)

    font_candidates = [
        "DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/data/data/com.termux/files/usr/share/fonts/TTF/DejaVuSans.ttf",
        "arial.ttf",
    ]

    max_w = card_w - 2*36
    max_h = card_h - 2*42
    font, ml = _fit_font(d, text.strip(), font_candidates, max_w, max_h, start=66, min_size=20)

    if hasattr(d, "multiline_textbbox"):
        b = d.multiline_textbbox((0,0), ml, font=font, spacing=10, align="center")
        tw, th = (b[2]-b[0]), (b[3]-b[1])
    else:
        tw, th = d.multiline_textsize(ml, font=font, spacing=10)

    tx = (size - tw)//2
    ty = (size - th)//2 + 4

    glow = Image.new("RGBA", (size, size), (0,0,0,0))
    gd = ImageDraw.Draw(glow)
    gd.multiline_text((tx, ty), ml, font=font, fill=(accent[0], accent[1], accent[2], 200),
                      spacing=10, align="center", stroke_width=6, stroke_fill=(accent[0], accent[1], accent[2], 200))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=12))
    bg = Image.alpha_composite(bg, glow)

    d.multiline_text((tx+4, ty+6), ml, font=font, fill=(0,0,0,170), spacing=10, align="center")
    d.multiline_text((tx, ty), ml, font=font, fill=(255,255,255,255), spacing=10, align="center",
                     stroke_width=3, stroke_fill=(0,0,0,220))
    bg = Image.alpha_composite(bg, overlay)

    # sticker mask + outline + shadow
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((18, 18, size-18, size-18), radius=140, fill=255)

    shaped = Image.new("RGBA", (size, size), (0,0,0,0))
    shaped.paste(bg, (0,0), mask)

    alpha = shaped.split()[-1]
    outline = alpha.filter(ImageFilter.MaxFilter(size=23))
    outline_img = Image.new("RGBA", (size, size), (255,255,255,255))
    outline_img.putalpha(outline)

    shadow2 = outline.filter(ImageFilter.GaussianBlur(radius=11))
    shadow_img = Image.new("RGBA", (size, size), (0,0,0,120))
    shadow_img.putalpha(shadow2)

    canvas = Image.new("RGBA", (size, size), (0,0,0,0))
    canvas = Image.alpha_composite(canvas, ImageChops.offset(shadow_img, 6, 12))
    canvas = Image.alpha_composite(canvas, outline_img)
    canvas = Image.alpha_composite(canvas, shaped)
    return canvas
# ---------- end renderer ----------

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

@client.on(events.NewMessage(incoming=True))
async def auto_reply(event):
    global auto_reply_active, auto_reply_count, last_auto_reply_time
    sender = await event.get_sender()
    if auto_reply_active and event.is_private and not is_bot(sender):
        await event.reply(default_reply)
        auto_reply_count += 1
        last_auto_reply_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

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

    img = build_premium_text_sticker(text_to_render, size=512)

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

        # اگر قبلاً همین پیام به پک اضافه شده، پک آپدیت نشود
        if _already_added_to_pack(event.sender_id, event.chat_id, reply.id):
            try:
                await event.delete()
            except Exception:
                pass
            return

        # استخراج document
        sent_msg = sent[0] if isinstance(sent, (list, tuple)) and sent else sent
        doc = getattr(sent_msg, "document", None)
        if doc is None and getattr(sent_msg, "media", None) is not None:
            doc = getattr(sent_msg.media, "document", None)

        if doc is not None:
            try:
                await _add_sticker_to_admin_pack(event.sender_id, doc, emoji="📝")
                _mark_added_to_pack(event.sender_id, event.chat_id, reply.id)
                await _maybe_send_pack_preview_to_saved(event.sender_id, out_path)
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

async def main():
    await client.start(phone=phone_number)
    print("Client Created and Online")
    await client.run_until_disconnected()

client.loop.run_until_complete(main())
PY

log "Python file '${PYTHON_FILE}' has been created."
python3 "$PYTHON_FILE"
