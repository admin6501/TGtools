from telethon import TelegramClient, events
import asyncio
from datetime import datetime

# دریافت اطلاعات حساب کاربری از کاربر
api_id = input("Please enter your API ID: ")
api_hash = input("Please enter your API Hash: ")
phone_number = input("Please enter your phone number: ")
channel_username = input("Please enter the channel username (e.g., @channelusername): ")

# ایجاد یک کلاینت تلگرام
client = TelegramClient('session_name', api_id, api_hash)

# متغیرهای کنترل
keep_alive_active = False
auto_reply_active = False
default_reply = "صبور باشید در اسرع وقت پاسخگو هستم."
auto_reply_count = 0
last_auto_reply_time = None
admins = []  # لیست ادمین‌ها

async def get_admins():
    """دریافت لیست ادمین‌های کانال"""
    global admins
    async for participant in client.iter_participants(channel_username, filter=events.ChannelParticipantsAdmins):
        admins.append(participant.id)

async def is_admin(user_id):
    """بررسی اینکه آیا کاربر ادمین است یا خیر"""
    return user_id in admins

async def keep_alive():
    """تابعی که پیام‌ها را به صورت خودکار ارسال می‌کند"""
    global keep_alive_active
    while keep_alive_active:
        await client.send_message(channel_username, 'Keeping the channel active')
        await asyncio.sleep(5)  # هر 5 ثانیه یکبار پیام ارسال می‌شود

# دستور .keepalive برای شروع ارسال پیام‌های خودکار
@client.on(events.NewMessage(pattern=r'\.keepalive'))
async def start_keep_alive(event):
    if await is_admin(event.sender_id):
        global keep_alive_active
        if not keep_alive_active:
            keep_alive_active = True
            await event.reply("Keepalive started!")
            asyncio.create_task(keep_alive())
        else:
            await event.reply("Keepalive is already active.")
    else:
        await event.reply("You are not authorized to use this command.")

# دستور .stopalive برای توقف ارسال پیام‌های خودکار
@client.on(events.NewMessage(pattern=r'\.stopalive'))
async def stop_keep_alive(event):
    if await is_admin(event.sender_id):
        global keep_alive_active
        if keep_alive_active:
            keep_alive_active = False
            await event.reply("Keepalive stopped!")
        else:
            await event.reply("Keepalive is not active.")
    else:
        await event.reply("You are not authorized to use this command.")

# دستور .startpish برای فعال کردن پاسخ خودکار
@client.on(events.NewMessage(pattern=r'\.startpish'))
async def start_auto_reply(event):
    if await is_admin(event.sender_id):
        global auto_reply_active
        if not auto_reply_active:
            auto_reply_active = True
            await event.reply("Auto-reply started!")
        else:
            await event.reply("Auto-reply is already active.")
    else:
        await event.reply("You are not authorized to use this command.")

# دستور .stoppish برای غیرفعال کردن پاسخ خودکار
@client.on(events.NewMessage(pattern=r'\.stoppish'))
async def stop_auto_reply(event):
    if await is_admin(event.sender_id):
        global auto_reply_active
        if auto_reply_active:
            auto_reply_active = False
            await event.reply("Auto-reply stopped!")
        else:
            await event.reply("Auto-reply is not active.")
    else:
        await event.reply("You are not authorized to use this command.")

# دستور .edit برای ویرایش پیام پیشفرض پاسخ خودکار
@client.on(events.NewMessage(pattern=r'\.edit (.+)'))
async def edit_auto_reply(event):
    if await is_admin(event.sender_id):
        global default_reply
        new_reply = event.pattern_match.group(1)
        default_reply = new_reply
        await event.reply(f"Auto-reply message updated to: {default_reply}")
    else:
        await event.reply("You are not authorized to use this command.")

# دریافت پیام‌ها و ارسال پاسخ خودکار در صورت فعال بودن و پیام از چت خصوصی باشد
@client.on(events.NewMessage(incoming=True))
async def auto_reply(event):
    global auto_reply_active, default_reply, auto_reply_count, last_auto_reply_time
    # اگر پاسخ خودکار فعال بود و پیام دریافتی از یک چت خصوصی بود
    if auto_reply_active and event.is_private:
        await event.reply(default_reply)
        auto_reply_count += 1
        last_auto_reply_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

# دستور .status برای نمایش وضعیت بات
@client.on(events.NewMessage(pattern=r'\.status'))
async def status(event):
    global keep_alive_active, auto_reply_active, auto_reply_count, last_auto_reply_time
    status_message = (
        f"Bot Status:\n"
        f"Auto-reply: {'Active' if auto_reply_active else 'Inactive'}\n"
        f"Keepalive: {'Active' if keep_alive_active else 'Inactive'}\n"
        f"Auto-reply count: {auto_reply_count}\n"
        f"Last auto-reply time: {last_auto_reply_time if last_auto_reply_time else 'No replies yet'}"
    )
    await event.reply(status_message)

async def main():
    # اتصال به حساب کاربری
    await client.start(phone=phone_number)
    print("Client Created and Online")

    # دریافت لیست ادمین‌ها
    await get_admins()

    # نگه داشتن کلاینت آنلاین و دریافت دستورات
    await client.run_until_disconnected()

# اجرای برنامه
client.loop.run_until_complete(main())
