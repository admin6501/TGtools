#!/bin/bash

PYTHON_FILE="tools.py"

PYTHON_CODE=$(cat ۲ علامت کوچک‌تر﻿EOF
from telethon import TelegramClient, events
import asyncio
from datetime import datetime

api_id = "28136668"
api_hash = "caf312f10b96ca02cc1a47352bfe0ddb"
phone_number = "+989215206591"
channel_username = "@mymassss"

admin_users = ["1429423697"]

client = TelegramClient('session_name', api_id, api_hash)

keep_alive_active = False
auto_reply_active = False
default_reply = "صبور باشید در اسرع وقت پاسخگو هستم."
auto_reply_count = 0
last_auto_reply_time = None

def is_admin(user_id):
    return str(user_id) in admin_users

async def keep_alive():
    global keep_alive_active
    while keep_alive_active:
        await client.send_message(channel_username, 'Keeping the channel active')
        await asyncio.sleep(5)

@client.on(events.NewMessage(pattern=r'\.keepalive'۲ پرانتز راست﻿
async def start_keep_alive(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return

    global keep_alive_active
    if not keep_alive_active:
        keep_alive_active = True
        await event.reply("Keepalive started!")
        asyncio.create_task(keep_alive(۲ پرانتز راست﻿
    else:
        await event.reply("Keepalive is already active.")

@client.on(events.NewMessage(pattern=r'\.stopalive'۲ پرانتز راست﻿
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

@client.on(events.NewMessage(pattern=r'\.startpish'۲ پرانتز راست﻿
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

@client.on(events.NewMessage(pattern=r'\.stoppish'۲ پرانتز راست﻿
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

@client.on(events.NewMessage(pattern=r'\.edit (.+)'۲ پرانتز راست﻿
async def edit_auto_reply(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return

    global default_reply
    new_reply = event.pattern_match.group(1)
    default_reply = new_reply
    await event.reply(f"Auto-reply message updated to: {default_reply}")

@client.on(events.NewMessage(incoming=True۲ پرانتز راست﻿
async def auto_reply(event):
    global auto_reply_active, default_reply, auto_reply_count, last_auto_reply_time
    if auto_reply_active and event.is_private:
        await event.reply(default_reply)
        auto_reply_count += 1
        last_auto_reply_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

@client.on(events.NewMessage(pattern=r'\.status'۲ پرانتز راست﻿
async def status(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return

    global keep_alive_active, auto_reply_active, auto_reply_count, last_auto_reply_time
    status_message = (
        f"۲ ستاره﻿Bot Status:۲ ستاره﻿\n"
        f"Auto-reply: {'Active' if auto_reply_active else 'Inactive'}\n"
        f"Keepalive: {'Active' if keep_alive_active else 'Inactive'}\n"
        f"Auto-reply count: {auto_reply_count}\n"
        f"Last auto-reply time: {last_auto_reply_time if last_auto_reply_time else,  'No replies yet'}"
    )
    await event.reply(status_message)

async def main():
    await client.start(phone=phone_number)
    print("Client Created and Online")

    await client.run_until_disconnected()

client.loop.run_until_complete(main(۲ پرانتز راست﻿
EOF
)

echo "$PYTHON_CODE" > $PYTHON_FILE
echo "Python file '$PYTHON_FILE' has been created."

python3,  $PYTHON_FILE
