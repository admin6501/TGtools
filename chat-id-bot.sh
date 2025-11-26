#!/bin/bash

echo "------------------------------------"
echo "   Telegram Username → ID Installer "
echo "------------------------------------"

# === گرفتن اطلاعات از کاربر ===
read -p "API_ID را وارد کنید: " API_ID
read -p "API_HASH را وارد کنید: " API_HASH
read -p "BOT_TOKEN را وارد کنید: " BOT_TOKEN

echo ""
echo "در حال نصب پیش‌نیازها..."

# === نصب پایتون و pip در صورت نیاز ===
if ! command -v python3 &> /dev/null
then
    echo "Python3 نصب نیست. در حال نصب..."
    sudo apt update 2>/dev/null || sudo yum update -y
    sudo apt install -y python3 python3-pip 2>/dev/null || sudo yum install -y python3 python3-pip
else
    echo "Python3 نصب است."
fi

if ! command -v pip3 &> /dev/null
then
    echo "pip نصب نیست. در حال نصب..."
    sudo apt install -y python3-pip 2>/dev/null || sudo yum install -y python3-pip
else
    echo "pip نصب است."
fi

# === نصب کتابخانه‌ها ===
echo "در حال نصب کتابخانه‌ها..."
pip3 install --upgrade pip
pip3 install telethon python-telegram-bot==20.7

# === ساخت فایل ربات با اصلاح Event Loop برای سرور ===
echo "ساخت فایل bot_auto_username.py با اصلاح Event Loop و بدون خطا..."

cat <<EOF > bot_auto_username.py
from telethon import TelegramClient
from telegram import Update
from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, ContextTypes, filters
import asyncio

API_ID = ${API_ID}
API_HASH = "${API_HASH}"
BOT_TOKEN = "${BOT_TOKEN}"
SESSION = "user_session"

tele_client = TelegramClient(SESSION, API_ID, API_HASH)

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("سلام! یک یوزرنیم با @ بفرست تا آیدی عددی آن را ارسال کنم.")

async def handle_username(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = update.message.text.strip()
    if not text.startswith("@"):
        await update.message.reply_text("پیام باید با @ شروع شود.")
        return
    username = text.lstrip("@")
    try:
        entity = await tele_client.get_entity(username)
        user_id = entity.id
        await update.message.reply_text(f"آیدی عددی @{username}:\n\`{user_id}\`", parse_mode="Markdown")
    except Exception as e:
        await update.message.reply_text(f
