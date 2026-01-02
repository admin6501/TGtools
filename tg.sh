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
  install_system_packages || true
  ensure_python_and_pip
  log "Installing Python dependencies (telethon, pillow)..."
  pip_install telethon pillow || die "Failed to install required Python packages."
  download_vazirmatn_font
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
<UNCHANGED PYTHON CODE>
PY

log "Python file '${PYTHON_FILE}' has been created."
python3 "$PYTHON_FILE"