#!/usr/bin/env bash
set -euo pipefail

PYTHON_FILE="tools.py"

have() { command -v "$1" >/dev/null 2>&1; }

SUDO=""
if [[ "${EUID:-$(id -u)}" -ne 0 ]] && have sudo; then
  SUDO="sudo"
fi

install_system_packages() {
  if have apt-get; then
    $SUDO apt-get update -y || true
    $SUDO apt-get install -y python3 python3-pip fonts-dejavu-core libwebp-tools || true
  elif have pkg; then
    pkg install -y python python-pip ttf-dejavu libwebp || true
  fi
}

install_python_deps() {
  python3 -m pip install --upgrade pip >/dev/null 2>&1 || true
  python3 -m pip install telethon pillow
}

install_system_packages
install_python_deps

read -rp "API ID: " API_ID
read -rp "API Hash: " API_HASH
read -rp "Phone Number: " PHONE
read -rp "Channel Username: " CHANNEL
read -rp "Admin IDs (comma separated): " ADMINS

export TG_API_ID="$API_ID"
export TG_API_HASH="$API_HASH"
export TG_PHONE_NUMBER="$PHONE"
export TG_CHANNEL_USERNAME="$CHANNEL"
export TG_ADMIN_USERS="$ADMINS"

cat > "$PYTHON_FILE" <<'PY'
from telethon import TelegramClient, events, utils
from telethon.tl.functions.stickers import CreateStickerSetRequest, AddStickerToSetRequest
from telethon.tl.types import InputStickerSetShortName, InputStickerSetItem
from telethon.tl.functions.messages import GetStickerSetRequest

from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
import os, tempfile, json, random, hashlib, textwrap, math, asyncio

api_id = int(os.environ["TG_API_ID"])
api_hash = os.environ["TG_API_HASH"]
phone = os.environ["TG_PHONE_NUMBER"]
admins = [x.strip() for x in os.environ["TG_ADMIN_USERS"].split(",")]

client = TelegramClient("session", api_id, api_hash)
STATE_FILE = "sticker_state.json"

def load_state():
    if os.path.exists(STATE_FILE):
        return json.load(open(STATE_FILE))
    return {}

def save_state(s):
    json.dump(s, open(STATE_FILE, "w"), indent=2)

def seeded_rng(t):
    return random.Random(int(hashlib.sha256(t.encode()).hexdigest()[:16], 16))

def fit_font(draw, text, max_w, max_h):
    fonts = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "DejaVuSans.ttf"
    ]
    for size in range(64, 18, -2):
        for f in fonts:
            try:
                font = ImageFont.truetype(f, size)
            except:
                continue
            lines = textwrap.wrap(text, 24)
            txt = "\n".join(lines)
            box = draw.multiline_textbbox((0,0), txt, font=font, spacing=8)
            if box[2] <= max_w and box[3] <= max_h:
                return font, txt
    return ImageFont.load_default(), text

def build_premium(text):
    size = 512
    rng = seeded_rng(text)

    themes = [
        ((12,14,24),(20,28,40),(60,180,200)),
        ((18,18,18),(32,32,32),(220,180,90)),
        ((16,12,24),(28,20,40),(200,90,180))
    ]
    bg1, bg2, accent = rng.choice(themes)

    img = Image.new("RGBA",(size,size))
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t=y/size
        r=int(bg1[0]*(1-t)+bg2[0]*t)
        g=int(bg1[1]*(1-t)+bg2[1]*t)
        b=int(bg1[2]*(1-t)+bg2[2]*t)
        draw.line((0,y,size,y),(r,g,b))

    img = img.filter(ImageFilter.GaussianBlur(2))

    overlay = Image.new("RGBA",(size,size),(0,0,0,0))
    d = ImageDraw.Draw(overlay)

    pad=44
    box=(pad,pad,size-pad,size-pad)
    d.rounded_rectangle(box,40,fill=(15,15,18,160))
    img = Image.alpha_composite(img, overlay)

    text_layer = Image.new("RGBA",(size,size),(0,0,0,0))
    td = ImageDraw.Draw(text_layer)
    font, txt = fit_font(td,text,size-140,size-140)
    w,h = td.multiline_textbbox((0,0),txt,font=font)[2:]
    x=(size-w)//2
    y=(size-h)//2

    glow = Image.new("RGBA",(size,size),(0,0,0,0))
    gd = ImageDraw.Draw(glow)
    gd.multiline_text((x,y),txt,font=font,fill=(*accent,200),align="center")
    glow = glow.filter(ImageFilter.GaussianBlur(12))
    img = Image.alpha_composite(img, glow)

    td.multiline_text((x,y),txt,font=font,fill=(255,255,255,255),align="center",stroke_width=2,stroke_fill=(0,0,0,200))
    img = Image.alpha_composite(img, text_layer)

    mask = Image.new("L",(size,size),0)
    ImageDraw.Draw(mask).rounded_rectangle((10,10,size-10,size-10),120,fill=255)
    final = Image.new("RGBA",(size,size))
    final.paste(img,(0,0),mask)

    return final

def is_admin(uid):
    return str(uid) in admins

@client.on(events.NewMessage(pattern=r"\.st$"))
async def st(event):
    if not is_admin(event.sender_id) or not event.is_reply:
        return
    reply = await event.get_reply_message()
    if not reply.text:
        return

    img = build_premium(reply.text)
    path = tempfile.mktemp(suffix=".webp")
    img.save(path,"WEBP",quality=95)

    sent = await client.send_file(event.chat_id,path,reply_to=reply.id)

    state = load_state()
    aid=str(event.sender_id)
    state.setdefault(aid,{"seen":[],"pack":None,"sent":False})

    key=f"{event.chat_id}:{reply.id}"
    if key not in state[aid]["seen"]:
        doc=sent.document
        if not state[aid]["pack"]:
            short=f"p_{aid}_{random.randint(1000,9999)}"
            await client(CreateStickerSetRequest(
                user_id=await client.get_input_entity("me"),
                title="Premium Text Stickers",
                short_name=short,
                stickers=[InputStickerSetItem(utils.get_input_document(doc),"📝")]
            ))
            state[aid]["pack"]=short
        else:
            await client(AddStickerToSetRequest(
                stickerset=InputStickerSetShortName(state[aid]["pack"]),
                sticker=InputStickerSetItem(utils.get_input_document(doc),"📝")
            ))
        state[aid]["seen"].append(key)

        if not state[aid]["sent"]:
            await client.send_file("me",path)
            state[aid]["sent"]=True

    save_state(state)
    os.remove(path)
    await event.delete()

async def main():
    await client.start(phone=phone)
    print("Bot is running")
    await client.run_until_disconnected()

client.loop.run_until_complete(main())
PY

python3 "$PYTHON_FILE"
