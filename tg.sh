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

banned_users = set()

def is_admin(user_id):
    return str(user_id) in admin_users

def is_bot(user):
    return user.bot

def is_banned(user_id):
    return str(user_id) in banned_users

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
        ".ban <user_id> - Ban a user.\n"
        ".unban <user_id> - Unban a user.\n"
        ".status - Show bot status.\n"
    )
    await event.reply(help_message)

@client.on(events.NewMessage(pattern=r'\.ban (\d+)'))
async def ban_user(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return

    user_id = event.pattern_match.group(1)
    banned_users.add(user_id)
    await event.reply(f"User {user_id} has been banned.")

@client.on(events.NewMessage(pattern=r'\.unban (\d+)'))
async def unban_user(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return

    user_id = event.pattern_match.group(1)
    if user_id in banned_users:
        banned_users.remove(user_id)
        await event.reply(f"User {user_id} has been unbanned.")
    else:
        await event.reply(f"User
