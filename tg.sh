#!/usr/bin/env bash
set -euo pipefail

PYTHON_FILE="tools.py"

# --- Vazirmatn font ---
VZ_FONT_FILE="Vazirmatn-Regular.ttf"
VZ_FONT_URL="https://github.com/rastikerdar/vazirmatn/raw/master/dist/Vazirmatn-Regular.ttf"
# ----------------------

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
  if is_termux; then
    log "Detected Termux. Installing packages via pkg..."
    pkg update -y || true
    pkg install -y python python-pip libwebp freetype fontconfig || true
    pkg install -y ttf-dejavu || true
    pkg install -y curl wget || true
    return 0
  fi

  if have apt-get; then
    log "Detected apt-get. Installing packages..."
    $SUDO apt-get update -y || true
    $SUDO apt-get install -y python3 python3-pip python3-venv || true
    $SUDO apt-get install -y fonts-dejavu-core webp || true
    $SUDO apt-get install -y libwebp-tools || true
    $SUDO apt-get install -y curl wget || true
    return 0
  fi

  if have dnf; then
    log "Detected dnf. Installing packages..."
    $SUDO dnf install -y python3 python3-pip || true
    $SUDO dnf install -y dejavu-sans-fonts libwebp-tools || true
    $SUDO dnf install -y curl wget || true
    return 0
  fi

  if have yum; then
    log "Detected yum. Installing packages..."
    $SUDO yum install -y python3 python3-pip || true
    $SUDO yum install -y dejavu-sans-fonts libwebp-tools || true
    $SUDO yum install -y curl wget || true
    return 0
  fi

  if have pacman; then
    log "Detected pacman. Installing packages..."
    $SUDO pacman -Sy --noconfirm python python-pip || true
    $SUDO pacman -S --noconfirm ttf-dejavu libwebp || true
    $SUDO pacman -S --noconfirm curl wget || true
    return 0
  fi

  if have apk; then
    log "Detected apk. Installing packages..."
    $SUDO apk add --no-cache python3 py3-pip || true
    $SUDO apk add --no-cache ttf-dejavu libwebp-tools || true
    $SUDO apk add --no-cache curl wget || true
    return 0
  fi

  if have zypper; then
    log "Detected zypper. Installing packages..."
    $SUDO zypper --non-interactive install python3 python3-pip || true
    $SUDO zypper --non-interactive install dejavu-fonts webp || true
    $SUDO zypper --non-interactive install curl wget || true
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

# Check if a Python package is importable
py_pkg_installed() {
  python3 -c "import $1" >/dev/null 2>&1
}

download_vazirmatn_font() {
  if [[ -f "$VZ_FONT_FILE" ]]; then
    log "Vazirmatn font already exists: $VZ_FONT_FILE"
    return 0
  fi

  log "Downloading Vazirmatn font to ./$VZ_FONT_FILE ..."
  if have curl; then
    curl -L --fail -o "$VZ_FONT_FILE" "$VZ_FONT_URL" || true
  elif have wget; then
    wget -O "$VZ_FONT_FILE" "$VZ_FONT_URL" || true
  else
    warn "Neither curl nor wget is available. Can't auto-download Vazirmatn."
  fi

  if [[ ! -f "$VZ_FONT_FILE" ]]; then
    warn "Could not download Vazirmatn font automatically."
    warn "Manual fix: place Vazirmatn-Regular.ttf next to tg.sh and rerun."
  else
    log "Downloaded Vazirmatn: $VZ_FONT_FILE"
  fi
}

preflight() {
  log "Preflight: checking prerequisites..."

  # 1) Check python3 & pip
  local need_sys=false
  if ! have python3; then
    log "python3 not found."
    need_sys=true
  elif ! python3 -m pip --version >/dev/null 2>&1; then
    log "pip not found."
    need_sys=true
  else
    log "python3 and pip are already installed."
  fi

  if $need_sys; then
    log "Installing system packages..."
    install_system_packages || true
    ensure_python_and_pip
  fi

  # 2) Check Python libraries (telethon, pillow, python-dotenv)
  local missing_pkgs=()
  if ! py_pkg_installed telethon; then
    missing_pkgs+=("telethon")
  fi
  if ! py_pkg_installed PIL; then
    missing_pkgs+=("pillow")
  fi
  if ! py_pkg_installed dotenv; then
    missing_pkgs+=("python-dotenv")
  fi

  if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
    log "Missing Python packages: ${missing_pkgs[*]}. Installing..."
    pip_install "${missing_pkgs[@]}" || die "Failed to install required Python packages."
  else
    log "All Python dependencies (telethon, pillow, python-dotenv) are already installed."
  fi

  # 2b) Check emergentintegrations (Emergent AI library) from custom index
  if ! py_pkg_installed emergentintegrations; then
    log "Installing emergentintegrations (Emergent AI library)..."
    python3 -m pip install emergentintegrations --extra-index-url https://d33sy5i8bnduwe.cloudfront.net/simple/ \
      || python3 -m pip install --user emergentintegrations --extra-index-url https://d33sy5i8bnduwe.cloudfront.net/simple/ \
      || warn "Could not install emergentintegrations. AI auto-reply will fall back to the default message."
  else
    log "emergentintegrations is already installed."
  fi

  # 3) Check curl/wget (needed for font download)
  if ! have curl && ! have wget; then
    log "Neither curl nor wget found. Installing..."
    install_system_packages || true
  fi

  # 4) Check Vazirmatn font
  download_vazirmatn_font

  log "Preflight complete."
}

# ---------- main ----------
preflight

read -r -p "Please enter your API ID: " api_id
read -r -p "Please enter your API Hash: " api_hash
read -r -p "Please enter your phone number: " phone_number
read -r -p "Please enter admin user IDs (comma separated): " admin_users
read -r -p "Please enter your Emergent LLM key (sk-emergent-...): " emergent_key

export TG_API_ID="$api_id"
export TG_API_HASH="$api_hash"
export TG_PHONE_NUMBER="$phone_number"
export TG_ADMIN_USERS="$admin_users"
export TG_EMERGENT_LLM_KEY="$emergent_key"

cat > "$PYTHON_FILE" <<'PY'
from telethon import TelegramClient, events, utils, errors
import asyncio
import time
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
import base64

from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

from telethon.tl.functions.messages import GetStickerSetRequest
from telethon.tl.functions.stickers import CreateStickerSetRequest, AddStickerToSetRequest
from telethon.tl.types import InputStickerSetShortName, InputStickerSetItem
from telethon.tl.functions.account import UpdateStatusRequest

from dotenv import load_dotenv
load_dotenv()

try:
    from emergentintegrations.llm.chat import LlmChat, UserMessage, ImageContent
    _AI_AVAILABLE = True
except Exception:
    _AI_AVAILABLE = False


def _env(name: str, required: bool = True) -> str:
    v = os.environ.get(name, "").strip()
    if required and not v:
        raise RuntimeError(f"Missing required env var: {name}")
    return v


# BUG FIX: api_id must be int for TelegramClient
api_id = int(_env("TG_API_ID"))
api_hash = _env("TG_API_HASH")
phone_number = _env("TG_PHONE_NUMBER")
EMERGENT_LLM_KEY = _env("TG_EMERGENT_LLM_KEY", required=False)

admin_users_raw = _env("TG_ADMIN_USERS")
admin_users = [x.strip() for x in admin_users_raw.split(",") if x.strip()]

client = TelegramClient("session_name", api_id, api_hash)

keep_alive_active = False
auto_reply_active = False
default_reply = "\u0635\u0628\u0648\u0631 \u0628\u0627\u0634\u06cc\u062f \u062f\u0631 \u0627\u0633\u0631\u0639 \u0648\u0642\u062a \u067e\u0627\u0633\u062e\u06af\u0648 \u0647\u0633\u062a\u0645."
auto_reply_count = 0
last_auto_reply_time = None

# ---- AI auto-reply config ----
current_provider = "anthropic"
current_model = "claude-sonnet-4-6"

ALLOWED_MODELS = {
    "openai": ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5-mini", "gpt-4o", "gpt-4o-mini"],
    "anthropic": ["claude-opus-4-7", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"],
    "gemini": ["gemini-3.1-pro-preview", "gemini-3-flash-preview", "gemini-2.5-pro", "gemini-2.5-flash"],
}

PERSONAS = {
    "formal": "\u062a\u0648 \u062f\u0633\u062a\u06cc\u0627\u0631 \u0634\u062e\u0635\u06cc \u0635\u0627\u062d\u0628 \u0627\u06cc\u0646 \u0627\u06a9\u0627\u0646\u062a \u062a\u0644\u06af\u0631\u0627\u0645 \u0647\u0633\u062a\u06cc \u0648 \u062f\u0631 \u0646\u0628\u0648\u062f \u0627\u0648 \u067e\u0627\u0633\u062e \u0645\u06cc\u200c\u062f\u0647\u06cc. \u0628\u0627 \u0644\u062d\u0646\u06cc \u0631\u0633\u0645\u06cc\u060c \u0645\u0648\u062f\u0628\u0627\u0646\u0647 \u0648 \u0645\u062d\u062a\u0631\u0645\u0627\u0646\u0647 \u0648 \u0641\u0642\u0637 \u0628\u0647 \u0632\u0628\u0627\u0646 \u0641\u0627\u0631\u0633\u06cc \u067e\u0627\u0633\u062e \u0628\u062f\u0647. \u06a9\u0648\u062a\u0627\u0647 \u0648 \u062f\u0642\u06cc\u0642 \u062c\u0648\u0627\u0628 \u0628\u062f\u0647.",
    "friendly": "\u062a\u0648 \u062f\u0633\u062a\u06cc\u0627\u0631 \u0634\u062e\u0635\u06cc \u0635\u0627\u062d\u0628 \u0627\u06cc\u0646 \u0627\u06a9\u0627\u0646\u062a \u062a\u0644\u06af\u0631\u0627\u0645 \u0647\u0633\u062a\u06cc \u0648 \u062f\u0631 \u0646\u0628\u0648\u062f \u0627\u0648 \u067e\u0627\u0633\u062e \u0645\u06cc\u200c\u062f\u0647\u06cc. \u0628\u0627 \u0644\u062d\u0646\u06cc \u062e\u0648\u062f\u0645\u0648\u0646\u06cc\u060c \u06af\u0631\u0645 \u0648 \u062f\u0648\u0633\u062a\u0627\u0646\u0647 \u0648 \u0641\u0642\u0637 \u0628\u0647 \u0632\u0628\u0627\u0646 \u0641\u0627\u0631\u0633\u06cc \u067e\u0627\u0633\u062e \u0628\u062f\u0647. \u06a9\u0648\u062a\u0627\u0647 \u0648 \u0635\u0645\u06cc\u0645\u06cc \u062c\u0648\u0627\u0628 \u0628\u062f\u0647.",
    "professional": "\u062a\u0648 \u062f\u0633\u062a\u06cc\u0627\u0631 \u067e\u0634\u062a\u06cc\u0628\u0627\u0646\u06cc \u0635\u0627\u062d\u0628 \u0627\u06cc\u0646 \u0627\u06a9\u0627\u0646\u062a \u062a\u0644\u06af\u0631\u0627\u0645 \u0647\u0633\u062a\u06cc. \u0628\u0627 \u0644\u062d\u0646\u06cc \u062d\u0631\u0641\u0647\u200c\u0627\u06cc\u060c \u0645\u062e\u062a\u0635\u0631 \u0648 \u0631\u0627\u0647\u200c\u06af\u0634\u0627 \u0648 \u0641\u0642\u0637 \u0628\u0647 \u0632\u0628\u0627\u0646 \u0641\u0627\u0631\u0633\u06cc \u067e\u0627\u0633\u062e \u0628\u062f\u0647. \u0627\u06af\u0631 \u0633\u0648\u0627\u0644 \u0646\u06cc\u0627\u0632 \u0628\u0647 \u062f\u062e\u0627\u0644\u062a \u0634\u062e\u0635 \u0627\u0635\u0644\u06cc \u062f\u0627\u0631\u062f\u060c \u0628\u06af\u0648 \u06a9\u0647 \u062f\u0631 \u0627\u0648\u0644\u06cc\u0646 \u0641\u0631\u0635\u062a \u067e\u0627\u0633\u062e \u062f\u0627\u062f\u0647 \u0645\u06cc\u200c\u0634\u0648\u062f.",
    "witty": "\u062a\u0648 \u062f\u0633\u062a\u06cc\u0627\u0631 \u0634\u062e\u0635\u06cc \u0635\u0627\u062d\u0628 \u0627\u06cc\u0646 \u0627\u06a9\u0627\u0646\u062a \u062a\u0644\u06af\u0631\u0627\u0645 \u0647\u0633\u062a\u06cc \u0648 \u062f\u0631 \u0646\u0628\u0648\u062f \u0627\u0648 \u067e\u0627\u0633\u062e \u0645\u06cc\u200c\u062f\u0647\u06cc. \u0628\u0627 \u0644\u062d\u0646\u06cc \u0628\u0627\u0646\u0645\u06a9\u060c \u0628\u0627\u0647\u0648\u0634 \u0648 \u06a9\u0645\u06cc \u0634\u0648\u062e \u0648 \u0641\u0642\u0637 \u0628\u0647 \u0632\u0628\u0627\u0646 \u0641\u0627\u0631\u0633\u06cc \u067e\u0627\u0633\u062e \u0628\u062f\u0647. \u06a9\u0648\u062a\u0627\u0647 \u062c\u0648\u0627\u0628 \u0628\u062f\u0647.",
}
current_persona = "friendly"
custom_prompt = ""

# Auto-reply cooldown (seconds) per user. 0 = no limit.
auto_reply_cooldown = 0
_user_last_reply = {}

# user_id -> LlmChat instance (per-user multi-turn session)
ai_sessions = {}

def _system_prompt():
    if current_persona == "custom" and custom_prompt.strip():
        return custom_prompt.strip()
    return PERSONAS.get(current_persona, PERSONAS["friendly"])

def _reset_ai_sessions():
    global ai_sessions
    ai_sessions = {}

async def _ai_generate(user_id, text):
    if not _AI_AVAILABLE or not EMERGENT_LLM_KEY:
        return None
    try:
        chat = ai_sessions.get(user_id)
        if chat is None:
            chat = LlmChat(
                api_key=EMERGENT_LLM_KEY,
                session_id=f"tg_{user_id}",
                system_message=_system_prompt(),
            ).with_model(current_provider, current_model)
            ai_sessions[user_id] = chat
        resp = await chat.send_message(UserMessage(text=text))
        if isinstance(resp, str):
            return resp.strip()
        return str(resp).strip()
    except Exception as e:
        print(f"AI error: {e}")
        return None

# Convert an image (base64) to text using the configured vision-capable model.
async def _image_to_text(image_b64):
    if not _AI_AVAILABLE or not EMERGENT_LLM_KEY:
        return None
    try:
        ocr_chat = LlmChat(
            api_key=EMERGENT_LLM_KEY,
            session_id=f"ocr_{int(time.time() * 1000)}",
            system_message=(
                "\u062a\u0648 \u06cc\u06a9 \u0627\u0628\u0632\u0627\u0631 \u0627\u0633\u062a\u062e\u0631\u0627\u062c \u0645\u062a\u0646 \u0648 \u062a\u0648\u0635\u06cc\u0641 \u062a\u0635\u0648\u06cc\u0631 \u0647\u0633\u062a\u06cc."
            ),
        ).with_model(current_provider, current_model)
        prompt = (
            "\u0627\u06af\u0631 \u062f\u0631 \u0627\u06cc\u0646 \u062a\u0635\u0648\u06cc\u0631 \u0645\u062a\u0646\u06cc \u0648\u062c\u0648\u062f \u062f\u0627\u0631\u062f\u060c "
            "\u0622\u0646 \u0631\u0627 \u062f\u0642\u06cc\u0642 \u0648 \u06a9\u0627\u0645\u0644 \u0648 \u0628\u062f\u0648\u0646 \u062a\u063a\u06cc\u06cc\u0631 \u0627\u0633\u062a\u062e\u0631\u0627\u062c \u06a9\u0646. "
            "\u0627\u06af\u0631 \u0645\u062a\u0646\u06cc \u0648\u062c\u0648\u062f \u0646\u062f\u0627\u0631\u062f\u060c \u0645\u062d\u062a\u0648\u0627\u06cc \u062a\u0635\u0648\u06cc\u0631 \u0631\u0627 \u0628\u0647 \u0641\u0627\u0631\u0633\u06cc \u062a\u0648\u0635\u06cc\u0641 \u06a9\u0646. "
            "\u0641\u0642\u0637 \u0646\u062a\u06cc\u062c\u0647\u200c\u06cc \u0646\u0647\u0627\u06cc\u06cc \u0631\u0627 \u0628\u062f\u0647."
        )
        resp = await ocr_chat.send_message(
            UserMessage(text=prompt, file_contents=[ImageContent(image_base64=image_b64)])
        )
        if isinstance(resp, str):
            return resp.strip()
        return str(resp).strip()
    except Exception as e:
        print(f"OCR error: {e}")
        return None

# Translate text into a target language using the configured model.
async def _translate(text, target_lang):
    if not _AI_AVAILABLE or not EMERGENT_LLM_KEY:
        return None
    try:
        tchat = LlmChat(
            api_key=EMERGENT_LLM_KEY,
            session_id=f"tr_{int(time.time() * 1000)}",
            system_message="\u062a\u0648 \u06cc\u06a9 \u0645\u062a\u0631\u062c\u0645 \u062d\u0631\u0641\u0647\u200c\u0627\u06cc \u0647\u0633\u062a\u06cc. \u0641\u0642\u0637 \u0645\u062a\u0646 \u062a\u0631\u062c\u0645\u0647\u200c\u0634\u062f\u0647 \u0631\u0627 \u0628\u062f\u0647\u060c \u0628\u062f\u0648\u0646 \u062a\u0648\u0636\u06cc\u062d \u0627\u0636\u0627\u0641\u0647.",
        ).with_model(current_provider, current_model)
        prompt = (
            f"\u0645\u062a\u0646 \u0632\u06cc\u0631 \u0631\u0627 \u0628\u0647 \u0632\u0628\u0627\u0646 \u00ab{target_lang}\u00bb \u062a\u0631\u062c\u0645\u0647 \u06a9\u0646 \u0648 \u0641\u0642\u0637 \u062a\u0631\u062c\u0645\u0647 \u0631\u0627 \u062e\u0631\u0648\u062c\u06cc \u0628\u062f\u0647:\n\n"
            + text
        )
        resp = await tchat.send_message(UserMessage(text=prompt))
        if isinstance(resp, str):
            return resp.strip()
        return str(resp).strip()
    except Exception as e:
        print(f"Translate error: {e}")
        return None

# ---- persistent settings (survive restart / service reload) ----
CONFIG_FILE = "bot_config.json"

def _load_config():
    global current_provider, current_model, current_persona, custom_prompt
    global auto_reply_cooldown, default_reply, auto_reply_active, keep_alive_active
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception:
        return
    if not isinstance(cfg, dict):
        return
    current_provider = cfg.get("provider", current_provider)
    current_model = cfg.get("model", current_model)
    current_persona = cfg.get("persona", current_persona)
    custom_prompt = cfg.get("custom_prompt", custom_prompt)
    try:
        auto_reply_cooldown = int(cfg.get("cooldown", auto_reply_cooldown))
    except Exception:
        pass
    default_reply = cfg.get("default_reply", default_reply)
    auto_reply_active = bool(cfg.get("auto_reply_active", auto_reply_active))
    keep_alive_active = bool(cfg.get("keep_alive_active", keep_alive_active))

def _save_config():
    cfg = {
        "provider": current_provider,
        "model": current_model,
        "persona": current_persona,
        "custom_prompt": custom_prompt,
        "cooldown": auto_reply_cooldown,
        "default_reply": default_reply,
        "auto_reply_active": auto_reply_active,
        "keep_alive_active": keep_alive_active,
    }
    try:
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
    except Exception:
        pass

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
        pass

async def _get_or_create_pack_for_admin(admin_id: int, first_doc, emoji: str = "\U0001f4dd") -> str:
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

    title = (f"{sender_name} \u2022 Premium Text Stickers")[:64]
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
            _set_admin_info(admin_id, info)
            return candidate

        except errors.RPCError as e:
            if _is_name_occupied(e):
                continue
            raise

    raise RuntimeError("Could not allocate a unique sticker pack short_name after multiple attempts.")

async def _add_sticker_to_admin_pack(admin_id: int, doc, emoji: str = "\U0001f4dd") -> str:
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

# Removes the repeated authorization boilerplate from every command handler.
def admin_only(handler):
    async def wrapper(event):
        if not is_admin(event.sender_id):
            await event.reply("You are not authorized to use this command.")
            return
        return await handler(event)
    return wrapper

# BUG FIX: safe is_bot - handles None user
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
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(n):
        r = rng.randint(40, 120)
        x = rng.randint(-20, w + 20)
        y = rng.randint(-20, h + 20)
        col = (255, 255, 255, rng.randint(12, 35))
        d.ellipse((x - r, y - r, x + r, y + r), fill=col)
    layer = layer.filter(ImageFilter.GaussianBlur(radius=14))
    return Image.alpha_composite(base, layer)

def _accent_sweep(base: Image.Image, accent_rgb):
    size = base.size[0]
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.polygon([(int(size * 0.15), 0), (int(size * 0.55), 0), (int(size * 0.35), size), (int(size * -0.05), size)],
              fill=(accent_rgb[0], accent_rgb[1], accent_rgb[2], 22))
    layer = layer.filter(ImageFilter.GaussianBlur(radius=22))
    return Image.alpha_composite(base, layer)

# BUG FIX: Vazirmatn font added to font_candidates
def _fit_font(draw: ImageDraw.ImageDraw, text: str, font_candidates: list, max_w: int, max_h: int, start: int = 66, min_size: int = 20):
    def bbox(multiline: str, fnt):
        if hasattr(draw, "multiline_textbbox"):
            b = draw.multiline_textbbox((0, 0), multiline, font=fnt, spacing=10, align="center")
            return (b[2] - b[0]), (b[3] - b[1])
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

    for fs in range(start, min_size - 1, -2):
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
    card = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cd = ImageDraw.Draw(card)

    pad = 44
    card_w = size - 2 * pad
    card_h = int(size * 0.56)
    x0 = pad
    y0 = (size - card_h) // 2
    x1 = x0 + card_w
    y1 = y0 + card_h

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((x0 + 6, y0 + 12, x1 + 6, y1 + 12), radius=56, fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=16))
    bg = Image.alpha_composite(bg, shadow)

    cd.rounded_rectangle((x0, y0, x1, y1), radius=56, fill=(12, 14, 18, 150), outline=(255, 255, 255, 70), width=2)

    ring = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    rd.rounded_rectangle((x0 + 10, y0 + 10, x1 - 10, y1 - 10), radius=48, outline=(accent[0], accent[1], accent[2], 90), width=3)
    ring = ring.filter(ImageFilter.GaussianBlur(radius=0.6))
    card = Image.alpha_composite(card, ring)

    bg = Image.alpha_composite(bg, card)

    # text
    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)

    # BUG FIX: Vazirmatn added as first font candidate for Persian text support
    font_candidates = [
        "Vazirmatn-Regular.ttf",
        "./Vazirmatn-Regular.ttf",
        "DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/data/data/com.termux/files/usr/share/fonts/TTF/DejaVuSans.ttf",
        "arial.ttf",
    ]

    max_w = card_w - 2 * 36
    max_h = card_h - 2 * 42
    font, ml = _fit_font(d, text.strip(), font_candidates, max_w, max_h, start=66, min_size=20)

    if hasattr(d, "multiline_textbbox"):
        b = d.multiline_textbbox((0, 0), ml, font=font, spacing=10, align="center")
        tw, th = (b[2] - b[0]), (b[3] - b[1])
    else:
        tw, th = d.multiline_textsize(ml, font=font, spacing=10)

    tx = (size - tw) // 2
    ty = (size - th) // 2 + 4

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.multiline_text((tx, ty), ml, font=font, fill=(accent[0], accent[1], accent[2], 200),
                       spacing=10, align="center", stroke_width=6, stroke_fill=(accent[0], accent[1], accent[2], 200))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=12))
    bg = Image.alpha_composite(bg, glow)

    d.multiline_text((tx + 4, ty + 6), ml, font=font, fill=(0, 0, 0, 170), spacing=10, align="center")
    d.multiline_text((tx, ty), ml, font=font, fill=(255, 255, 255, 255), spacing=10, align="center",
                     stroke_width=3, stroke_fill=(0, 0, 0, 220))
    bg = Image.alpha_composite(bg, overlay)

    # sticker mask + outline + shadow
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((18, 18, size - 18, size - 18), radius=140, fill=255)

    shaped = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shaped.paste(bg, (0, 0), mask)

    alpha = shaped.split()[-1]
    outline = alpha.filter(ImageFilter.MaxFilter(size=23))
    outline_img = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    outline_img.putalpha(outline)

    shadow2 = outline.filter(ImageFilter.GaussianBlur(radius=11))
    shadow_img = Image.new("RGBA", (size, size), (0, 0, 0, 120))
    shadow_img.putalpha(shadow2)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas = Image.alpha_composite(canvas, ImageChops.offset(shadow_img, 6, 12))
    canvas = Image.alpha_composite(canvas, outline_img)
    canvas = Image.alpha_composite(canvas, shaped)
    return canvas
# ---------- end renderer ----------

async def keep_alive():
    # Keep the account shown as "online" by periodically refreshing the online
    # status. No messages are sent to any channel/chat.
    global keep_alive_active
    while keep_alive_active:
        try:
            await client(UpdateStatusRequest(offline=False))
        except Exception:
            pass
        await asyncio.sleep(30)

@client.on(events.NewMessage(pattern=r"\.keepalive"))
@admin_only
async def start_keep_alive(event):
    global keep_alive_active
    if not keep_alive_active:
        keep_alive_active = True
        _save_config()
        await event.reply("Keepalive started!")
        asyncio.create_task(keep_alive())
    else:
        await event.reply("Keepalive is already active.")

@client.on(events.NewMessage(pattern=r"\.stopalive"))
@admin_only
async def stop_keep_alive(event):
    global keep_alive_active
    if keep_alive_active:
        keep_alive_active = False
        _save_config()
        await event.reply("Keepalive stopped!")
    else:
        await event.reply("Keepalive is not active.")

@client.on(events.NewMessage(pattern=r"\.startpish"))
@admin_only
async def start_auto_reply(event):
    global auto_reply_active
    if not auto_reply_active:
        auto_reply_active = True
        _save_config()
        await event.reply("Auto-reply started!")
    else:
        await event.reply("Auto-reply is already active.")

@client.on(events.NewMessage(pattern=r"\.stoppish"))
@admin_only
async def stop_auto_reply(event):
    global auto_reply_active
    if auto_reply_active:
        auto_reply_active = False
        _save_config()
        await event.reply("Auto-reply stopped!")
    else:
        await event.reply("Auto-reply is not active.")

@client.on(events.NewMessage(pattern=r"\.edit (.+)"))
@admin_only
async def edit_auto_reply(event):
    global default_reply
    default_reply = event.pattern_match.group(1)
    _save_config()
    await event.reply(f"Auto-reply message updated to: {default_reply}")

# BUG FIX: .help and .status handlers moved BEFORE auto_reply
# so admin commands in private chats are not swallowed by auto_reply
@client.on(events.NewMessage(pattern=r"\.help"))
@admin_only
async def show_help(event):
    help_message = (
        "**Available Commands (\u0641\u0642\u0637 \u0627\u062f\u0645\u06cc\u0646):**\n"
        ".keepalive - \u0634\u0631\u0648\u0639 \u0622\u0646\u0644\u0627\u06cc\u0646 \u0646\u06af\u0647\u200c\u062f\u0627\u0634\u062a\u0646 \u0627\u06a9\u0627\u0646\u062a (\u0628\u062f\u0648\u0646 \u0627\u0631\u0633\u0627\u0644 \u067e\u06cc\u0627\u0645).\n"
        ".stopalive - \u062a\u0648\u0642\u0641 \u0622\u0646\u0644\u0627\u06cc\u0646 \u0646\u06af\u0647\u200c\u062f\u0627\u0634\u062a\u0646.\n"
        ".startpish - \u0634\u0631\u0648\u0639 \u067e\u0627\u0633\u062e \u062e\u0648\u062f\u06a9\u0627\u0631 \u0628\u0627 \u0647\u0648\u0634 \u0645\u0635\u0646\u0648\u0639\u06cc.\n"
        ".stoppish - \u062a\u0648\u0642\u0641 \u067e\u0627\u0633\u062e \u062e\u0648\u062f\u06a9\u0627\u0631.\n"
        ".model - \u0646\u0645\u0627\u06cc\u0634/\u062a\u063a\u06cc\u06cc\u0631 \u0645\u062f\u0644 \u0647\u0648\u0634 \u0645\u0635\u0646\u0648\u0639\u06cc.\n"
        ".persona - \u0646\u0645\u0627\u06cc\u0634/\u062a\u063a\u06cc\u06cc\u0631 \u0634\u062e\u0635\u06cc\u062a \u0648 \u0644\u062d\u0646 \u067e\u0627\u0633\u062e.\n"
        ".setprompt <\u0645\u062a\u0646> - \u062a\u0646\u0638\u06cc\u0645 \u067e\u0631\u0627\u0645\u067e\u062a \u062f\u0644\u062e\u0648\u0627\u0647.\n"
        ".cooldown <\u062b\u0627\u0646\u06cc\u0647> - \u0641\u0627\u0635\u0644\u0647\u200c\u06cc \u0632\u0645\u0627\u0646\u06cc \u067e\u0627\u0633\u062e \u062e\u0648\u062f\u06a9\u0627\u0631 \u0628\u0631\u0627\u06cc \u0647\u0631 \u06a9\u0627\u0631\u0628\u0631.\n"
        ".edit <message> - \u062a\u0646\u0638\u06cc\u0645 \u067e\u06cc\u0627\u0645 \u067e\u06cc\u0634\u200c\u0641\u0631\u0636 (\u0648\u0642\u062a\u06cc AI \u062f\u0631 \u062f\u0633\u062a\u0631\u0633 \u0646\u06cc\u0633\u062a).\n"
        ".st - \u062a\u0628\u062f\u06cc\u0644 \u0645\u062a\u0646 \u0631\u06cc\u067e\u0644\u0627\u06cc\u200c\u0634\u062f\u0647 \u0628\u0647 \u0627\u0633\u062a\u06cc\u06a9\u0631.\n"
        ".ocr - \u0631\u06cc\u067e\u0644\u0627\u06cc \u0631\u0648\u06cc \u0639\u06a9\u0633: \u0627\u0633\u062a\u062e\u0631\u0627\u062c \u0645\u062a\u0646/\u062a\u0648\u0635\u06cc\u0641 \u0648 \u0627\u0631\u0633\u0627\u0644 \u0628\u0647 Saved Messages.\n"
        ".tr [\u0632\u0628\u0627\u0646] - \u062a\u0631\u062c\u0645\u0647\u200c\u06cc \u067e\u06cc\u0627\u0645 \u0631\u06cc\u067e\u0644\u0627\u06cc\u200c\u0634\u062f\u0647 \u06cc\u0627 \u0645\u062a\u0646 (\u067e\u06cc\u0634\u200c\u0641\u0631\u0636 \u0641\u0627\u0631\u0633\u06cc).\n"
        ".status - \u0646\u0645\u0627\u06cc\u0634 \u0648\u0636\u0639\u06cc\u062a \u0631\u0628\u0627\u062a.\n"
    )
    await event.reply(help_message)

@client.on(events.NewMessage(pattern=r"\.status"))
@admin_only
async def status(event):
    status_message = (
        f"**Bot Status:**\n"
        f"Auto-reply: {'Active' if auto_reply_active else 'Inactive'}\n"
        f"Keepalive: {'Active' if keep_alive_active else 'Inactive'}\n"
        f"AI model: {current_provider} / {current_model}\n"
        f"Persona: {current_persona}\n"
        f"Cooldown: {auto_reply_cooldown}s\n"
        f"AI available: {'Yes' if (_AI_AVAILABLE and EMERGENT_LLM_KEY) else 'No'}\n"
        f"Auto-reply count: {auto_reply_count}\n"
        f"Last auto-reply time: {last_auto_reply_time if last_auto_reply_time else 'No replies yet'}"
    )
    await event.reply(status_message)

@client.on(events.NewMessage(pattern=r"\.st(?!\w)"))
@admin_only
async def text_to_sticker(event):
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

        if _already_added_to_pack(event.sender_id, event.chat_id, reply.id):
            try:
                await event.delete()
            except Exception:
                pass
            return

        sent_msg = sent[0] if isinstance(sent, (list, tuple)) and sent else sent
        doc = getattr(sent_msg, "document", None)
        if doc is None and getattr(sent_msg, "media", None) is not None:
            doc = getattr(sent_msg.media, "document", None)

        if doc is not None:
            try:
                await _add_sticker_to_admin_pack(event.sender_id, doc, emoji="\U0001f4dd")
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

# ---- AI configuration commands (configurable from Telegram) ----
@client.on(events.NewMessage(pattern=r"^\.ocr(?:\s|$)"))
@admin_only
async def image_to_text_cmd(event):
    if not event.is_reply:
        await event.reply("\u0631\u0648\u06cc \u06cc\u06a9 \u0639\u06a9\u0633 \u0631\u06cc\u067e\u0644\u0627\u06cc \u06a9\u0646 \u0648 \u0628\u0639\u062f .ocr \u0628\u0641\u0631\u0633\u062a.")
        return
    reply = await event.get_reply_message()
    has_image = bool(
        reply and (
            reply.photo
            or (reply.document and (getattr(reply.document, "mime_type", "") or "").startswith("image/"))
        )
    )
    if not has_image:
        await event.reply("\u067e\u06cc\u0627\u0645 \u0631\u06cc\u067e\u0644\u0627\u06cc\u200c\u0634\u062f\u0647 \u0639\u06a9\u0633 \u0646\u062f\u0627\u0631\u062f.")
        return
    if not _AI_AVAILABLE or not EMERGENT_LLM_KEY:
        await event.reply("\u0647\u0648\u0634 \u0645\u0635\u0646\u0648\u0639\u06cc \u062f\u0631 \u062f\u0633\u062a\u0631\u0633 \u0646\u06cc\u0633\u062a (\u06a9\u0644\u06cc\u062f Emergent \u062a\u0646\u0638\u06cc\u0645 \u0646\u0634\u062f\u0647).")
        return
    try:
        data = await reply.download_media(file=bytes)
    except Exception:
        data = None
    if not data:
        await event.reply("\u062f\u0627\u0646\u0644\u0648\u062f \u0639\u06a9\u0633 \u0646\u0627\u0645\u0648\u0641\u0642 \u0628\u0648\u062f.")
        return
    image_b64 = base64.b64encode(data).decode("utf-8")
    text = await _image_to_text(image_b64)
    if not text:
        await event.reply("\u0627\u0633\u062a\u062e\u0631\u0627\u062c \u0645\u062a\u0646 \u0646\u0627\u0645\u0648\u0641\u0642 \u0628\u0648\u062f.")
        return
    full = "\U0001f4dd \u0645\u062a\u0646 \u0627\u0633\u062a\u062e\u0631\u0627\u062c\u200c\u0634\u062f\u0647 \u0627\u0632 \u0639\u06a9\u0633:\n\n" + text
    # Telegram message limit is ~4096 chars; chunk long results.
    for i in range(0, len(full), 4000):
        await client.send_message("me", full[i:i + 4000])
    confirm = "\u2705 \u0645\u062a\u0646 \u0639\u06a9\u0633 \u0627\u0633\u062a\u062e\u0631\u0627\u062c \u0648 \u0628\u0647 Saved Messages \u0627\u0631\u0633\u0627\u0644 \u0634\u062f."
    try:
        if event.out:
            await event.edit(confirm)
        else:
            await event.reply(confirm)
    except Exception:
        try:
            await event.reply(confirm)
        except Exception:
            pass

@client.on(events.NewMessage(pattern=r"^\.tr(?:\s+(?P<arg>[\s\S]+))?$"))
@admin_only
async def translate_cmd(event):
    if not _AI_AVAILABLE or not EMERGENT_LLM_KEY:
        await event.reply("\u0647\u0648\u0634 \u0645\u0635\u0646\u0648\u0639\u06cc \u062f\u0631 \u062f\u0633\u062a\u0631\u0633 \u0646\u06cc\u0633\u062a (\u06a9\u0644\u06cc\u062f Emergent \u062a\u0646\u0638\u06cc\u0645 \u0646\u0634\u062f\u0647).")
        return
    arg = (event.pattern_match.group("arg") or "").strip()
    target = "\u0641\u0627\u0631\u0633\u06cc"
    reply = await event.get_reply_message() if event.is_reply else None
    if reply is not None:
        src_text = (reply.raw_text or "").strip()
        if arg:
            target = arg
    else:
        src_text = arg
    if not src_text:
        await event.reply(
            "\u0631\u0648\u06cc \u06cc\u06a9 \u067e\u06cc\u0627\u0645 \u0631\u06cc\u067e\u0644\u0627\u06cc \u06a9\u0646 \u0648 .tr \u0628\u0641\u0631\u0633\u062a\u060c \u06cc\u0627 \u0628\u0647 \u0634\u06a9\u0644 `.tr <\u0645\u062a\u0646>` \u0627\u0633\u062a\u0641\u0627\u062f\u0647 \u06a9\u0646.\n"
            "\u0628\u0631\u0627\u06cc \u0632\u0628\u0627\u0646 \u0645\u0642\u0635\u062f: \u0631\u0648\u06cc \u067e\u06cc\u0627\u0645 \u0631\u06cc\u067e\u0644\u0627\u06cc \u06a9\u0646 \u0648 `.tr english` \u0628\u0641\u0631\u0633\u062a."
        )
        return
    translated = await _translate(src_text, target)
    if not translated:
        await event.reply("\u062a\u0631\u062c\u0645\u0647 \u0646\u0627\u0645\u0648\u0641\u0642 \u0628\u0648\u062f.")
        return
    if reply is not None:
        try:
            await reply.reply(translated)
        except Exception:
            await event.reply(translated)
    else:
        try:
            if event.out:
                await event.edit(translated)
            else:
                await event.reply(translated)
        except Exception:
            await event.reply(translated)

@client.on(events.NewMessage(pattern=r"^\.model(?:\s+(?P<provider>\S+)\s+(?P<model>\S+))?\s*$"))
@admin_only
async def set_model(event):
    global current_provider, current_model
    provider = event.pattern_match.group("provider")
    model = event.pattern_match.group("model")
    if not provider:
        lines = [f"**\u0645\u062f\u0644 \u0641\u0639\u0644\u06cc:** `{current_provider} / {current_model}`", "", "**\u0645\u062f\u0644\u200c\u0647\u0627\u06cc \u0645\u0648\u062c\u0648\u062f:**"]
        for prov, models in ALLOWED_MODELS.items():
            lines.append(f"\u2022 **{prov}**: " + ", ".join(f"`{m}`" for m in models))
        lines.append("")
        lines.append("\u0628\u0631\u0627\u06cc \u062a\u063a\u06cc\u06cc\u0631: `.model <provider> <model>`")
        lines.append("\u0645\u062b\u0627\u0644: `.model openai gpt-5.4`")
        await event.reply("\n".join(lines))
        return
    provider = provider.lower()
    if provider not in ALLOWED_MODELS:
        await event.reply("\u067e\u0631\u0648\u0648\u0627\u06cc\u062f\u0631 \u0646\u0627\u0645\u0639\u062a\u0628\u0631. \u06cc\u06a9\u06cc \u0627\u0632: " + ", ".join(ALLOWED_MODELS.keys()))
        return
    if model not in ALLOWED_MODELS[provider]:
        await event.reply(f"\u0645\u062f\u0644 \u0646\u0627\u0645\u0639\u062a\u0628\u0631 \u0628\u0631\u0627\u06cc {provider}.\n\u0645\u062f\u0644\u200c\u0647\u0627\u06cc \u0645\u062c\u0627\u0632: " + ", ".join(ALLOWED_MODELS[provider]))
        return
    current_provider = provider
    current_model = model
    _reset_ai_sessions()
    _save_config()
    await event.reply(f"\u0645\u062f\u0644 \u0647\u0648\u0634 \u0645\u0635\u0646\u0648\u0639\u06cc \u062a\u0646\u0638\u06cc\u0645 \u0634\u062f \u0631\u0648\u06cc: `{provider} / {model}`")

@client.on(events.NewMessage(pattern=r"^\.persona(?:\s+(?P<key>\S+))?\s*$"))
@admin_only
async def set_persona(event):
    global current_persona
    key = event.pattern_match.group("key")
    if not key:
        names = {
            "formal": "\u0631\u0633\u0645\u06cc \u0648 \u0645\u0648\u062f\u0628\u0627\u0646\u0647",
            "friendly": "\u062e\u0648\u062f\u0645\u0648\u0646\u06cc \u0648 \u062f\u0648\u0633\u062a\u0627\u0646\u0647",
            "professional": "\u062d\u0631\u0641\u0647\u200c\u0627\u06cc/\u067e\u0634\u062a\u06cc\u0628\u0627\u0646\u06cc",
            "witty": "\u0628\u0627\u0646\u0645\u06a9 \u0648 \u0634\u0648\u062e",
            "custom": "\u067e\u0631\u0627\u0645\u067e\u062a \u062f\u0644\u062e\u0648\u0627\u0647 (\u0628\u0627 .setprompt)",
        }
        lines = [f"**\u0634\u062e\u0635\u06cc\u062a \u0641\u0639\u0644\u06cc:** `{current_persona}`", "", "**\u0634\u062e\u0635\u06cc\u062a\u200c\u0647\u0627\u06cc \u0645\u0648\u062c\u0648\u062f:**"]
        for k, v in names.items():
            lines.append(f"\u2022 `{k}` \u2014 {v}")
        lines.append("")
        lines.append("\u0628\u0631\u0627\u06cc \u062a\u063a\u06cc\u06cc\u0631: `.persona <key>` \u0645\u062b\u0644 `.persona formal`")
        await event.reply("\n".join(lines))
        return
    key = key.lower()
    if key == "custom":
        if not custom_prompt.strip():
            await event.reply("\u0627\u0648\u0644 \u0628\u0627 \u062f\u0633\u062a\u0648\u0631 `.setprompt <\u0645\u062a\u0646>` \u067e\u0631\u0627\u0645\u067e\u062a \u062f\u0644\u062e\u0648\u0627\u0647\u062a \u0631\u0648 \u0628\u0630\u0627\u0631.")
            return
        current_persona = "custom"
        _reset_ai_sessions()
        _save_config()
        await event.reply("\u0634\u062e\u0635\u06cc\u062a \u0631\u0648\u06cc \u067e\u0631\u0627\u0645\u067e\u062a \u062f\u0644\u062e\u0648\u0627\u0647 \u062a\u0646\u0638\u06cc\u0645 \u0634\u062f.")
        return
    if key not in PERSONAS:
        await event.reply("\u0634\u062e\u0635\u06cc\u062a \u0646\u0627\u0645\u0639\u062a\u0628\u0631. \u0645\u0648\u062c\u0648\u062f: " + ", ".join(list(PERSONAS.keys()) + ["custom"]))
        return
    current_persona = key
    _reset_ai_sessions()
    _save_config()
    await event.reply(f"\u0634\u062e\u0635\u06cc\u062a \u062a\u0646\u0638\u06cc\u0645 \u0634\u062f \u0631\u0648\u06cc: `{key}`")

@client.on(events.NewMessage(pattern=r"^\.setprompt\s+([\s\S]+)$"))
@admin_only
async def set_custom_prompt(event):
    global custom_prompt, current_persona
    custom_prompt = event.pattern_match.group(1).strip()
    current_persona = "custom"
    _reset_ai_sessions()
    _save_config()
    await event.reply("\u067e\u0631\u0627\u0645\u067e\u062a \u062f\u0644\u062e\u0648\u0627\u0647 \u062b\u0628\u062a \u0634\u062f \u0648 \u0634\u062e\u0635\u06cc\u062a \u0631\u0648\u06cc custom \u062a\u0646\u0638\u06cc\u0645 \u0634\u062f.")

@client.on(events.NewMessage(pattern=r"^\.cooldown(?:\s+(?P<sec>\d+))?\s*$"))
@admin_only
async def set_cooldown(event):
    global auto_reply_cooldown
    sec = event.pattern_match.group("sec")
    if sec is None:
        await event.reply(
            f"**Cooldown \u0641\u0639\u0644\u06cc:** {auto_reply_cooldown} \u062b\u0627\u0646\u06cc\u0647\n"
            "\u0628\u0631\u0627\u06cc \u062a\u063a\u06cc\u06cc\u0631: `.cooldown <\u062b\u0627\u0646\u06cc\u0647>`\n"
            "\u0645\u062b\u0627\u0644: `.cooldown 30` (\u0639\u062f\u062f 0 \u06cc\u0639\u0646\u06cc \u0628\u062f\u0648\u0646 \u0645\u062d\u062f\u0648\u062f\u06cc\u062a)"
        )
        return
    auto_reply_cooldown = int(sec)
    _save_config()
    if auto_reply_cooldown == 0:
        await event.reply("Cooldown \u063a\u06cc\u0631\u0641\u0639\u0627\u0644 \u0634\u062f (\u0628\u062f\u0648\u0646 \u0645\u062d\u062f\u0648\u062f\u06cc\u062a).")
    else:
        await event.reply(f"Cooldown \u062a\u0646\u0638\u06cc\u0645 \u0634\u062f \u0631\u0648\u06cc {auto_reply_cooldown} \u062b\u0627\u0646\u06cc\u0647 \u0628\u0631\u0627\u06cc \u0647\u0631 \u06a9\u0627\u0631\u0628\u0631.")

# BUG FIX: auto_reply MUST be the LAST handler so it doesn't intercept admin commands
@client.on(events.NewMessage(incoming=True))
async def auto_reply(event):
    global auto_reply_active, auto_reply_count, last_auto_reply_time
    if not auto_reply_active or not event.is_private:
        return
    # Never auto-reply to command messages
    if (event.raw_text or "").strip().startswith("."):
        return
    sender = await event.get_sender()
    if is_bot(sender):
        return
    # Do not let the AI reply to admins' own messages
    if is_admin(event.sender_id):
        return
    # Per-user cooldown to avoid spamming replies / AI usage
    if auto_reply_cooldown > 0:
        now = time.time()
        last = _user_last_reply.get(event.sender_id, 0)
        if now - last < auto_reply_cooldown:
            return
        _user_last_reply[event.sender_id] = now
    text = (event.raw_text or "").strip()
    reply_text = None
    if text:
        reply_text = await _ai_generate(event.sender_id, text)
    if not reply_text:
        reply_text = default_reply
    await event.reply(reply_text)
    auto_reply_count += 1
    last_auto_reply_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

async def main():
    _load_config()
    await client.start(phone=phone_number)
    print("Client Created and Online")
    if keep_alive_active:
        asyncio.create_task(keep_alive())
    await client.run_until_disconnected()

client.loop.run_until_complete(main())
PY

log "Python file '${PYTHON_FILE}' has been created."

# Persist credentials to .env so the bot can run headless (systemd/nohup) without re-exporting.
cat > .env <<EOF
TG_API_ID=${api_id}
TG_API_HASH=${api_hash}
TG_PHONE_NUMBER=${phone_number}
TG_ADMIN_USERS=${admin_users}
TG_EMERGENT_LLM_KEY=${emergent_key}
EOF
chmod 600 .env 2>/dev/null || true
log "Saved credentials to .env (used for headless runs)."

echo
read -r -p "Run the bot permanently in the background? (no tmux/screen needed) [y/N]: " persist
persist="${persist:-N}"

if [[ "$persist" =~ ^[Yy]$ ]]; then
  log "Step 1/2: One-time Telegram login (you may be asked for the login code / 2FA password)..."
  python3 - <<'LOGIN'
import os
from telethon import TelegramClient
from dotenv import load_dotenv
load_dotenv()
api_id = int(os.environ["TG_API_ID"])
api_hash = os.environ["TG_API_HASH"]
phone = os.environ["TG_PHONE_NUMBER"]
with TelegramClient("session_name", api_id, api_hash) as client:
    client.start(phone=phone)
    me = client.get_me()
    print("Login OK. Logged in as:", getattr(me, "first_name", "user"))
LOGIN

  WORKDIR="$(pwd)"
  PYBIN="$(command -v python3)"

  can_root=false
  if [[ "${EUID:-$(id -u)}" -eq 0 || -n "$SUDO" ]]; then
    can_root=true
  fi

  if have systemctl && $can_root && ! is_termux; then
    SERVICE_NAME="tg-userbot"
    RUN_USER="$(id -un)"
    log "Step 2/2: Installing systemd service '${SERVICE_NAME}'..."
    $SUDO tee /etc/systemd/system/${SERVICE_NAME}.service >/dev/null <<EOF
[Unit]
Description=Telegram Userbot (tg.sh)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${WORKDIR}
ExecStart=${PYBIN} ${WORKDIR}/${PYTHON_FILE}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    $SUDO systemctl daemon-reload
    $SUDO systemctl enable ${SERVICE_NAME} >/dev/null 2>&1 || true
    $SUDO systemctl restart ${SERVICE_NAME}
    log "Done! The bot now runs as a service and auto-starts on reboot."
    log "Useful commands:"
    log "  Status: ${SUDO} systemctl status ${SERVICE_NAME}"
    log "  Logs:   ${SUDO} journalctl -u ${SERVICE_NAME} -f"
    log "  Stop:   ${SUDO} systemctl stop ${SERVICE_NAME}"
  else
    log "Step 2/2: systemd not available. Starting in background with nohup..."
    nohup "$PYBIN" "${WORKDIR}/${PYTHON_FILE}" > userbot.log 2>&1 &
    echo $! > userbot.pid
    log "Done! The bot is running in the background (PID $(cat userbot.pid))."
    log "  Logs: tail -f ${WORKDIR}/userbot.log"
    log "  Stop: kill \$(cat ${WORKDIR}/userbot.pid)"
    if is_termux; then
      log "Termux tip: run 'termux-wake-lock' and install Termux:Boot to survive reboots."
    fi
  fi
else
  log "Starting the bot in the foreground (press Ctrl+C to stop)..."
  python3 "$PYTHON_FILE"
fi
