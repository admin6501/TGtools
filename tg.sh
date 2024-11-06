#!/bin/bash

PYTHON_FILE="tools.py"

# دریافت اطلاعات از کاربر
read -p "Enter your API ID: " api_id
read -p "Enter your API Hash: " api_hash
read -p "Enter your phone number (including country code): " phone_number
read -p "Enter your channel username (e.g., @My_Channel): " channel_username
read -p "Enter the admin user ID(s) (comma-separated if multiple): " admin_users

# چک کردن نصب بودن Telethon و نصب آن در صورت عدم وجود
if ! python3 -c "import telethon" &> /dev/null; then
    echo "Installing Telethon..."
    pip install telethon
fi

PYTHON_CODE=$(cat <<EOF
from telethon import TelegramClient, events
import asyncio
from datetime import datetime

api_id = "$api_id"
api_hash = "$api_hash"
phone_number = "$phone_number"
channel_username = "$channel_username"

# تبدیل لیست شناسه‌های مدیران به فرمت مناسب
admin_users = [$admin_users]

client = TelegramClient('session_name', api_id, api_hash)

keep_alive_active = False
auto_reply_active = False
default_reply = "On shodam j midam"  # پیام پیش‌فرض Auto-reply

auto_reply_count = 0
last_auto_reply_time = None

def is_admin(user_id):
    return str(user_id) in admin_users

async def keep_alive():
    global keep_alive_active
    while keep_alive_active:
        await client.send_message(channel_username, 'Keeping the channel active')
        await asyncio.sleep(10)  # ارسال پیام هر 10 ثانیه

@client.on(events.NewMessage(pattern=r'\\.keepalive'))
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

@client.on(events.NewMessage(pattern=r'\\.stopalive'))
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

@client.on(events.NewMessage(pattern=r'\\.start'))
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

@client.on(events.NewMessage(pattern=r'\\.stop'))
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

@client.on(events.NewMessage(pattern=r'\\.edit (.+)'))
async def edit_auto_reply(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return

    global default_reply
    new_reply = event.pattern_match.group(1)
    default_reply = new_reply
    await event.reply(f"Auto-reply message updated to: {default_reply}")

@client.on(events.NewMessage(incoming=True))
async def auto_reply(event):
    global auto_reply_active, default_reply, auto_reply_count, last_auto_reply_time

    # چک کردن فعال بودن Auto Reply و اینکه پیام از طرف یک ربات نباشد و پیام خصوصی باشد
    if auto_reply_active and event.is_private and not (await event.get_sender()).bot:
        await event.reply(default_reply)
        auto_reply_count += 1
        last_auto_reply_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

@client.on(events.NewMessage(pattern=r'\\.status'))
async def status(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return

    global keep_alive_active, auto_reply_active, auto_reply_count, last_auto_reply_time
    status_message = (
        f"**Bot Status:**\\n"
        f"Auto-reply: {'Active' if auto_reply_active else 'Inactive'}\\n"
        f"Keepalive: {'Active' if keep_alive_active else 'Inactive'}\\n"
        f"Auto-reply count: {auto_reply_count}\\n"
        f"Last auto-reply time: {last_auto_reply_time if last_auto_reply_time else 'No replies yet'}"
    )
    await event.reply(status_message)

async def main():
    await client.start(phone=phone_number)
    print("Client Created and Online")

    await client.run_until_disconnected()

client.loop.run_until_complete(main())
EOF
)

# ایجاد فایل پایتون
echo "$PYTHON_CODE" > $PYTHON_FILE
echo "Python file '$PYTHON_FILE' has been created."

# اجرای فایل پایتون
python3 $PYTHON_FILE