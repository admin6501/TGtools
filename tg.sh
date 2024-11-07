#!/bin/bash

PYTHON_FILE="tools.py"

# دریافت اطلاعات مورد نیاز از کاربر
read -p "Please enter your API ID: " api_id
read -p "Please enter your API Hash: " api_hash
read -p "Please enter your phone number: " phone_number
read -p "Please enter your channel username: " channel_username
read -p "Please enter admin user IDs (comma separated): " admin_users

PYTHON_CODE=$(cat <<EOF
from telethon import TelegramClient, events
import asyncio
from datetime import datetime

api_id = "$api_id"
api_hash = "$api_hash"
phone_number = "$phone_number"
channel_username = "$channel_username"

admin_users = "$admin_users".split(',')

client = TelegramClient('session_name', api_id, api_hash)

keep_alive_active = False
auto_reply_active = False
default_reply = "صبور باشید در اسرع وقت پاسخگو هستم."
auto_reply_count = 0
last_auto_reply_time = None
bot_active = True

def is_admin(user_id):
    return str(user_id) in admin_users

def is_bot(user):
    return user.bot

async def keep_alive():
    global keep_alive_active
    while keep_alive_active:
        await client.send_message(channel_username, 'Keeping the channel active')
        await asyncio.sleep(5)

@client.on(events.NewMessage(pattern=r'\.keepalive'))
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

@client.on(events.NewMessage(pattern=r'\.stopalive'))
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

@client.on(events.NewMessage(pattern=r'\.startpish'))
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

@client.on(events.NewMessage(pattern=r'\.stoppish'))
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

@client.on(events.NewMessage(pattern=r'\.edit (.+)'))
async def edit_auto_reply(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return

    global default_reply
    new_reply = event.pattern_match.group(1)
    default_reply = new_reply
    await event.reply(f"Auto-reply message updated to: {default_reply}")

@client.on(events.NewMessage(pattern=r'\.help'))
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
        ".status - Show bot status.\n"
        ".stop - Disable all features.\n"
    )
    await event.reply(help_message)

@client.on(events.NewMessage(incoming=True))
async def auto_reply(event):
    global auto_reply_active, default_reply, auto_reply_count, last_auto_reply_time, bot_active
    sender = await event.get_sender()
    if bot_active and auto_reply_active and event.is_private and not is_bot(sender):
        await event.reply(default_reply)
        auto_reply_count += 1
        last_auto_reply_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"Auto-reply sent to {event.sender_id}")

@client.on(events.NewMessage(pattern=r'\.status'))
async def status(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return

    global keep_alive_active, auto_reply_active, auto_reply_count, last_auto_reply_time
    status_message = (
        f"**Bot Status:**\n"
        f"Auto-reply: {'Active' if auto_reply_active else 'Inactive'}\n"
        f"Keepalive: {'Active' if keep_alive_active else 'Inactive'}\n"
        f"Auto-reply count: {auto_reply_count}\n"
        f"Last auto-reply time: {last_auto_reply_time if last_auto_reply_time else 'No replies yet'}"
    )
    await event.reply(status_message)

@client.on(events.NewMessage(pattern=r'\.stop'))
async def stop_bot(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return

    global keep_alive_active, auto_reply_active, bot_active
    keep_alive_active = False
    auto_reply_active = False
    bot_active = False
    await event.reply("All features have been disabled.")

async def main():
    await client.start(phone=phone_number)
    print("Client Created and Online")

    await client.run_until_disconnected()

client.loop.run_until_complete(main())
EOF
)

echo "$PYTHON_CODE" > $PYTHON_FILE
echo "Python file '$PYTHON_FILE' has been created."

python3 $PYTHON_FILE
