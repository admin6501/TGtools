#!/bin/bash

# نام فایل پایتون
PYTHON_FILE="tools.py"

# محتوای کد پایتون که در فایل قرار می‌گیرد
PYTHON_CODE=$(cat <<EOF
from telethon import TelegramClient, events
import asyncio
from datetime import datetime
import requests
from bs4 import BeautifulSoup

api_id = input("Please enter your API ID: ")
api_hash = input("Please enter your API Hash: ")
phone_number = input("Please enter your phone number: ")
channel_username = input("Please enter the channel username (e.g., @channelusername): ")

# دریافت آیدی ادمین از کاربر
admin_user = input("Please enter the Admin User ID or Username: ")
admin_users = [admin_user]

client = TelegramClient('session_name', api_id, api_hash)

keep_alive_active = False
auto_reply_active = False
default_reply = "صبور باشید در اسرع وقت پاسخگو هستم."
auto_reply_count = 0
last_auto_reply_time = None
keep_typing_active = False

def is_admin(user_id):
    return str(user_id) in admin_users

async def keep_alive():
    global keep_alive_active
    while keep_alive_active:
        await client.send_message(channel_username, 'Keeping the channel active')
        await asyncio.sleep(5)

async def keep_typing():
    global keep_typing_active
    while keep_typing_active:
        await client.send_chat_action(channel_username, 'typing')
        await asyncio.sleep(4)

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

@client.on(events.NewMessage(incoming=True))
async def auto_reply(event):
    global auto_reply_active, default_reply, auto_reply_count, last_auto_reply_time
    if auto_reply_active and event.is_private:
        await event.reply(default_reply)
        auto_reply_count += 1
        last_auto_reply_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

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

@client.on(events.NewMessage(pattern=r'\.starttyping'))
async def start_typing(event):
    global keep_typing_active
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return
    if not keep_typing_active:
        keep_typing_active = True
        await event.reply("Typing simulation started!")
        asyncio.create_task(keep_typing())
    else:
        await event.reply("Typing simulation is already active.")

@client.on(events.NewMessage(pattern=r'\.stoptyping'))
async def stop_typing(event):
    global keep_typing_active
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return
    if keep_typing_active:
        keep_typing_active = False
        await event.reply("Typing simulation stopped!")
    else:
        await event.reply("Typing simulation is not active.")

@client.on(events.NewMessage(pattern=r'\.help'))
async def help_command(event):
    if not is_admin(event.sender_id):
        await event.reply("You are not authorized to use this command.")
        return
    help_message = (
        "**List of Available Commands:**\n\n"
        ".keepalive - Start sending 'Keepalive' messages to the channel.\n"
        ".stopalive - Stop sending 'Keepalive' messages.\n"
        ".startpish - Enable auto-reply to private messages.\n"
        ".stoppish - Disable auto-reply.\n"
        ".edit <message> - Edit the default auto-reply message.\n"
        ".status - Show the current status of the bot (auto-reply, keepalive, etc.).\n"
        ".starttyping - Start the typing simulation in the group/channel.\n"
        ".stoptyping - Stop the typing simulation.\n"
        ".help - Show this help message with a list of commands.\n"
        ".google <query> - Perform a Google search and return top 5 results.\n"
    )
    await event.reply(help_message)

@client.on(events.NewMessage(pattern=r'\.google (.+)'))
async def google_search(event):
    query = event.pattern_match.group(1)
    url = f"https://www.google.com/search?q={query.replace(' ', '+')}"
    response = requests.get(url)
    soup = BeautifulSoup(response.text, 'html.parser')
    results = []
    for g in soup.find_all('div', class_='BNeawe vvjwJb AP7Wnd'):
        results.append(g.get_text())
    if results:
        await event.reply("\n".join(results[:5]))  # نمایش ۵ نتیجه اول
    else:
        await event.reply("No results found.")

async def main():
    await client.start(phone=phone_number)
    print("Client Created and Online")
    await client.run_until_disconnected()

client.loop.run_until_complete(main())
EOF
)

# ایجاد فایل پایتون و نوشتن کد داخل آن
echo "$PYTHON_CODE" > $PYTHON_FILE
echo "Python file '$PYTHON_FILE' has been created."

# اجرای فایل پایتون
python3 $PYTHON_FILE