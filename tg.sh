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
  # Best-effort: python3/pip + optional font/webp tools
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
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
import json
import re
import random
import string
import hashlib
import math

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

# ---- Sticker pack state (per admin) ----
PACK_STATE_FILE = "sticker_packs.json"
_pack_state = None  # lazy-loaded
SEEN_LIMIT_PER_ADMIN = 2000

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

def _seen_key(chat_id: int, reply_id: int) -> str:
    return f"{chat_id}:{reply_id}"

def _already_added_to_pack(admin_id: int, chat_id: int, reply_id: int) -> bool:
    state = _load_pack_state()
    info = (state.get("packs", {}).get(str(admin_id)) or {})
    seen = info.get("seen") or []
    return _seen_key(chat_id, reply_id) in set(seen)

def _mark_added_to_pack(admin_id: int, chat_id: int, reply_id: int):
    state = _load_pack_state()
    packs = state.get("packs", {})
    admin_key = str(admin_id)
    info = packs.get(admin_key) or {}
    seen = info.get("seen") or []
    key = _seen_key(chat_id, reply_id)

    if key in set(seen):
        return

    seen.append(key)
    if len(seen) > SEEN_LIMIT_PER_ADMIN:
        seen = seen[-SEEN_LIMIT_PER_ADMIN:]

    info["seen"] = seen
    packs[admin_key] = info
    state["packs"] = packs
    _save_pack_state()

def _get_pack_info(admin_id: int) -> dict:
    state = _load_pack_state()
    return (state.get("packs", {}).get(str(admin_id)) or {})

def _set_pack_info(admin_id: int, new_info: dict):
    state = _load_pack_state()
    packs = state.get("packs", {})
    packs[str(admin_id)] = new_info
    state["packs"] = packs
    _save_pack_state()

def _ensure_pack_sent_flag(admin_id: int):
    info = _get_pack_info(admin_id)
    if "sent_pack_to_saved" not in info:
        info["sent_pack_to_saved"] = False
        _set_pack_info(admin_id, info)

async def _maybe_send_pack_to_saved_messages(admin_id: int, out_path: str):
    """
    ارسال «خود پک» به Saved Messages بدون لینک:
    یک بار، با ارسال همان فایل استیکری out_path به 'me' تا View Pack ظاهر شود.
    """
    try:
        info = _get_pack_info(admin_id)
        if info.get("sent_pack_to_saved", False):
            return
        # اگر هنوز پک/اطلاعاتش ثبت نشده، کاری نکن
        if not info.get("short_name"):
            return

        await client.send_file("me", out_path, caption="Sticker pack (preview)")
        info["sent_pack_to_saved"] = True
        _set_pack_info(admin_id, info)
    except Exception:
        # silent
        pass

async def _get_or_create_pack_for_admin(admin_id: int, first_doc, emoji: str = "📝") -> str:
    state = _load_pack_state()
    packs = state.get("packs", {})
    admin_key = str(admin_id)

    pack_info = packs.get(admin_key) or {}
    short_name = pack_info.get("short_name")
    if short_name and await _pack_exists(short_name):
        _ensure_pack_sent_flag(admin_id)
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

    base_short = _sanitize_short_name(f"tgst_{admin_id}_{base}")[:50]
    owner = await client.get_input_entity("me")
    item = InputStickerSetItem(document=utils.get_input_document(first_doc), emoji=emoji)

    for _ in range(12):
        suffix = "".join(random.choices(string.ascii_lowercase + string.digits, k=6))
        candidate = ((base_short if base_short else "tgst") + "_" + suffix)[:64]
        try:
            await client(CreateStickerSetRequest(
                user_id=owner,
                title=title,
                short_name=candidate,
                stickers=[item],
            ))

            packs[admin_key] = {
                "short_name": candidate,
                "title": title,
                "sent_pack_to_saved": False,  # حالا ارسال را داخل handler انجام می‌دهیم
                "seen": (packs.get(admin_key) or {}).get("seen", []),
            }
            state["packs"] = packs
            _save_pack_state()
            return candidate

        except errors.RPCError as e:
            if _is_name_occupied(e):
                continue
            raise

    raise RuntimeError("Could not allocate a unique sticker pack short_name after multiple attempts.")

async def _add_sticker_to_admin_pack(admin_id: int, doc, emoji: str = "📝") -> str:
    state = _load_pack_state()
    packs = state.get("packs", {})
    admin_key = str(admin_id)

    info = (packs.get(admin_key) or {})
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
    return user.bot

# ---------- Neon/Cyberpunk text sticker renderer ----------
def _seeded_rng(text: str) -> random.Random:
    h = hashlib.sha256(text.encode("utf-8")).hexdigest()
    seed = int(h[:16], 16)
    return random.Random(seed)

def _lerp(a, b, t: float):
    return int(a + (b - a) * t)

def _gradient_bg(size: int, c1, c2, angle_deg: float):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    px = img.load()
    ang = math.radians(angle_deg % 360)
    ux, uy = math.cos(ang), math.sin(ang)
    corners = [(0,0),(size-1,0),(0,size-1),(size-1,size-1)]
    proj = [x*ux + y*uy for x,y in corners]
    pmin, pmax = min(proj), max(proj)
    denom = (pmax - pmin) or 1.0
    for y in range(size):
        for x in range(size):
            t = ((x*ux + y*uy) - pmin) / denom
            r = _lerp(c1[0], c2[0], t)
            g = _lerp(c1[1], c2[1], t)
            b = _lerp(c1[2], c2[2], t)
            px[x, y] = (r, g, b, 255)
    return img

def _noise(img: Image.Image, rng: random.Random, amount: int = 10):
    w, h = img.size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    p = layer.load()
    for y in range(h):
        for x in range(w):
            v = rng.randint(-amount, amount)
            a = rng.randint(14, 34)
            p[x, y] = (v & 255, v & 255, v & 255, a)
    return Image.alpha_composite(img, layer)

def _blobs(img: Image.Image, rng: random.Random, n: int = 7):
    w, h = img.size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(n):
        cx = rng.randint(30, w-30)
        cy = rng.randint(30, h-30)
        rx = rng.randint(120, 260)
        ry = rng.randint(120, 260)
        col = (rng.randint(80, 255), rng.randint(80, 255), rng.randint(80, 255), rng.randint(60, 140))
        d.ellipse((cx-rx, cy-ry, cx+rx, cy+ry), fill=col)
    layer = layer.filter(ImageFilter.GaussianBlur(radius=22))
    return Image.alpha_composite(img, layer)

def _neon_lines(img: Image.Image, rng: random.Random):
    w, h = img.size
    layer = Image.new("RGBA", (w, h), (0,0,0,0))
    d = ImageDraw.Draw(layer)

    # خطوط مورب
    step = rng.randint(22, 34)
    col = (255, 255, 255, 34)
    for i in range(-h, w, step):
        d.line((i, 0, i + h, h), fill=col, width=2)

    # خطوط افقی نئونی کم‌رنگ
    for y in range(0, h, rng.randint(28, 40)):
        d.line((0, y, w, y), fill=(0, 0, 0, 20), width=2)

    layer = layer.filter(ImageFilter.GaussianBlur(radius=1.2))
    return Image.alpha_composite(img, layer)

def _fit_font(draw: ImageDraw.ImageDraw, text: str, font_candidates: list, max_w: int, max_h: int, start: int = 64, min_size: int = 20):
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

def build_neon_text_sticker(text: str, size: int = 512) -> Image.Image:
    rng = _seeded_rng(text)

    palettes = [
        ((18, 18, 40), (255, 0, 132)),
        ((10, 20, 30), (0, 206, 255)),
        ((20, 10, 30), (140, 255, 90)),
        ((15, 15, 18), (255, 210, 0)),
    ]
    base_dark, neon = rng.choice(palettes)
    angle = rng.uniform(0, 360)

    bg = _gradient_bg(size, base_dark, (neon[0]//2, neon[1]//2, neon[2]//2), angle)
    bg = _noise(bg, rng, amount=10)
    bg = _blobs(bg, rng, n=rng.randint(6, 9))
    bg = _neon_lines(bg, rng)

    # هاله‌ی مرکزی پشت متن
    glow = Image.new("RGBA", (size, size), (0,0,0,0))
    gd = ImageDraw.Draw(glow)
    cx, cy = size//2, size//2
    r = rng.randint(160, 210)
    gd.ellipse((cx-r, cy-r, cx+r, cy+r), fill=(neon[0], neon[1], neon[2], 90))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=28))
    bg = Image.alpha_composite(bg, glow)

    # glass box برای متن
    box = Image.new("RGBA", (size, size), (0,0,0,0))
    bd = ImageDraw.Draw(box)
    pad = 34
    box_w = size - 2*pad
    box_h = int(size*0.56)
    x0 = pad
    y0 = (size-box_h)//2
    x1 = x0 + box_w
    y1 = y0 + box_h
    bd.rounded_rectangle((x0, y0, x1, y1), radius=54, fill=(8, 10, 16, 140), outline=(255,255,255,70), width=2)

    # نوار نئونی بالای باکس
    bd.rounded_rectangle((x0+14, y0+14, x1-14, y0+40), radius=18, fill=(neon[0], neon[1], neon[2], 120))
    box = box.filter(ImageFilter.GaussianBlur(radius=0.8))
    bg = Image.alpha_composite(bg, box)

    overlay = Image.new("RGBA", (size, size), (0,0,0,0))
    d = ImageDraw.Draw(overlay)

    font_candidates = [
        "DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/data/data/com.termux/files/usr/share/fonts/TTF/DejaVuSans.ttf",
        "arial.ttf",
    ]

    max_w = box_w - 2*28
    max_h = box_h - 2*34
    font, ml = _fit_font(d, text.strip(), font_candidates, max_w, max_h, start=66, min_size=20)

    if hasattr(d, "multiline_textbbox"):
        b = d.multiline_textbbox((0,0), ml, font=font, spacing=10, align="center")
        tw, th = (b[2]-b[0]), (b[3]-b[1])
    else:
        tw, th = d.multiline_textsize(ml, font=font, spacing=10)

    tx = (size - tw)//2
    ty = (size - th)//2 + 6  # کمی پایین‌تر برای خوش‌فرم‌تر شدن

    # سایه
    d.multiline_text((tx+5, ty+7), ml, font=font, fill=(0,0,0,170), spacing=10, align="center")

    # glow رنگی متن (با لایه جدا)
    glow_text = Image.new("RGBA", (size, size), (0,0,0,0))
    gd2 = ImageDraw.Draw(glow_text)
    gd2.multiline_text(
        (tx, ty),
        ml,
        font=font,
        fill=(neon[0], neon[1], neon[2], 210),
        spacing=10,
        align="center",
        stroke_width=4,
        stroke_fill=(neon[0], neon[1], neon[2], 210),
    )
    glow_text = glow_text.filter(ImageFilter.GaussianBlur(radius=10))
    bg = Image.alpha_composite(bg, glow_text)

    # متن اصلی
    d.multiline_text(
        (tx, ty),
        ml,
        font=font,
        fill=(255,255,255,255),
        spacing=10,
        align="center",
        stroke_width=3,
        stroke_fill=(0,0,0,220),
    )
    bg = Image.alpha_composite(bg, overlay)

    # ماسک گرد و outline استیکری
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((18, 18, size-18, size-18), radius=130, fill=255)

    shaped = Image.new("RGBA", (size, size), (0,0,0,0))
    shaped.paste(bg, (0,0), mask)

    alpha = shaped.split()[-1]
    outline = alpha.filter(ImageFilter.MaxFilter(size=21))
    outline_img = Image.new("RGBA", (size, size), (255,255,255,255))
    outline_img.putalpha(outline)

    shadow = outline.filter(ImageFilter.GaussianBlur(radius=10))
    shadow_img = Image.new("RGBA", (size, size), (0,0,0,120))
    shadow_img.putalpha(shadow)

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

def is_admin(user_id):
    return str(user_id) in admin_users

def is_bot(user):
    return user.bot

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

    img = build_neon_text_sticker(text_to_render, size=512)

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

        # ارسال استیکر در چت
        sent = await client.send_file(event.chat_id, out_path, reply_to=reply.id, force_document=False)

        # اگر قبلاً همین پیام به پک اضافه شده، پک را آپدیت نکن
        if _already_added_to_pack(event.sender_id, event.chat_id, reply.id):
            try:
                await event.delete()
            except Exception:
                pass
            return

        # اضافه به پک (silent)
        sent_msg = sent[0] if isinstance(sent, (list, tuple)) and sent else sent
        doc = getattr(sent_msg, "document", None)
        if doc is None and getattr(sent_msg, "media", None) is not None:
            doc = getattr(sent_msg.media, "document", None)

        if doc is not None:
            try:
                await _add_sticker_to_admin_pack(event.sender_id, doc, emoji="📝")
                _mark_added_to_pack(event.sender_id, event.chat_id, reply.id)
                # معرفی پک در Saved Messages (پایدار) با ارسال out_path
                await _maybe_send_pack_to_saved_messages(event.sender_id, out_path)
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
