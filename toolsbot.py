from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, MessageHandler, Filters, ConversationHandler, CallbackContext
from telethon import TelegramClient, events
import asyncio

API_ID, API_HASH, PHONE, CHANNEL, ADMIN_ID, AUTH_CODE = range(6)

user_data = {}
auto_reply_active = False
default_reply = "صبور باشید در اسرع وقت پاسخگو هستم."
keep_alive_active = False

async def start_telegram_client(api_id, api_hash, phone_number, channel_username, admin_id, auth_code):
    client = TelegramClient('user_session', api_id, api_hash)
    await client.start(phone=phone_number, code_callback=lambda: auth_code)
    await client.send_message(channel_username, "ربات با موفقیت فعال شد")
    await client.send_message(admin_id, "ربات با موفقیت فعال شد")

    @client.on(events.NewMessage(incoming=True))
    async def handle_new_message(event):
        if auto_reply_active and event.is_private:
            await event.reply(default_reply)

    async def keep_alive():
        global keep_alive_active
        while keep_alive_active:
            await client.send_message(channel_username, "در حال نگه داشتن حساب آنلاین...")
            await asyncio.sleep(5)

    if keep_alive_active:
        asyncio.create_task(keep_alive())

    await client.run_until_disconnected()

def start(update: Update, _: CallbackContext) -> None:
    keyboard = [[InlineKeyboardButton("فعالسازی اسکریپت", callback_data='start_script')]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    update.message.reply_text("سلام! برای فعالسازی اسکریپت روی دکمه زیر کلیک کنید.", reply_markup=reply_markup)

def start_script_callback(update: Update, context: CallbackContext) -> int:
    query = update.callback_query
    query.answer()
    query.edit_message_text(text="برای استفاده از ربات لطفاً api_id خود را وارد کنید:")
    return API_ID

def api_id(update: Update, context: CallbackContext) -> int:
    user_data[update.effective_user.id] = {'api_id': update.message.text}
    update.message.reply_text("لطفاً api_hash خود را وارد کنید:")
    return API_HASH

def api_hash(update: Update, context: CallbackContext) -> int:
    user_data[update.effective_user.id]['api_hash'] = update.message.text
    update.message.reply_text("لطفاً شماره تلفن خود را وارد کنید (با کد کشور):")
    return PHONE

def phone(update: Update, context: CallbackContext) -> int:
    user_data[update.effective_user.id]['phone'] = update.message.text
    update.message.reply_text("لطفاً نام کاربری کانالی که می‌خواهید به آن پیام دهید را وارد کنید:")
    return CHANNEL

def channel(update: Update, context: CallbackContext) -> int:
    user_id = update.effective_user.id
    user_data[user_id]['channel_username'] = update.message.text
    update.message.reply_text("لطفاً admin ID خود را وارد کنید:")
    return ADMIN_ID

def admin_id(update: Update, context: CallbackContext) -> int:
    user_id = update.effective_user.id
    user_data[user_id]['admin_id'] = update.message.text
    update.message.reply_text("لطفاً کد احراز هویت تلگرام خود را وارد کنید:")
    return AUTH_CODE

def auth_code(update: Update, context: CallbackContext) -> int:
    user_id = update.effective_user.id
    user_data[user_id]['auth_code'] = update.message.text
    update.message.reply_text("در حال شروع ربات بر روی حساب شما. لطفاً صبور باشید...")
    asyncio.run(start_telegram_client(
        int(user_data[user_id]['api_id']),
        user_data[user_id]['api_hash'],
        user_data[user_id]['phone'],
        user_data[user_id]['channel_username'],
        user_data[user_id]['admin_id'],
        user_data[user_id]['auth_code']
    ))
    update.message.reply_text("ربات با موفقیت فعال شد و آماده به کار است!")
    return ConversationHandler.END

def auto_on(update: Update, _: CallbackContext) -> None:
    global auto_reply_active
    auto_reply_active = True
    update.message.reply_text("پاسخ خودکار فعال شد.")

def auto_off(update: Update, _: CallbackContext) -> None:
    global auto_reply_active
    auto_reply_active = False
    update.message.reply_text("پاسخ خودکار غیرفعال شد.")

def set_reply(update: Update, context: CallbackContext) -> None:
    global default_reply
    new_reply = ' '.join(context.args)
    if new_reply:
        default_reply = new_reply
        update.message.reply_text(f"پیام پاسخ خودکار به‌روز شد به: {default_reply}")
    else:
        update.message.reply_text("لطفاً یک پیام برای پاسخ خودکار وارد کنید.")

def keep_on(update: Update, _: CallbackContext) -> None:
    global keep_alive_active
    keep_alive_active = True
    update.message.reply_text("حالت نگه‌داشتن آنلاین فعال شد.")

def keep_off(update: Update, _: CallbackContext) -> None:
    global keep_alive_active
    keep_alive_active = False
    update.message.reply_text("حالت نگه‌داشتن آنلاین غیرفعال شد.")

def help_command(update: Update, _: CallbackContext) -> None:
    help_text = (
        "**دستورات ربات:**\n"
        "/start - شروع عملیات و تنظیمات اولیه\n"
        "/auto_on - فعال‌سازی پاسخ خودکار\n"
        "/auto_off - غیرفعال‌سازی پاسخ خودکار\n"
        "/set_reply <message> - تنظیم پیام پیش‌فرض برای پاسخ خودکار\n"
        "/keep_on - فعال‌سازی ارسال پیام هر پنج ثانیه برای نگه داشتن حساب آنلاین\n"
        "/keep_off - غیرفعال‌سازی نگه داشتن حساب آنلاین\n"
        "/help - نمایش این راهنما"
    )
    update.message.reply_text(help_text)

def cancel(update: Update, _: CallbackContext) -> int:
    update.message.reply_text("فرایند لغو شد.")
    return ConversationHandler.END

def main() -> None:
    token = input("لطفاً توکن ربات خود را وارد کنید: ")
    updater = Updater(token)

    conv_handler = ConversationHandler(
        entry_points=[CallbackQueryHandler(start_script_callback, pattern='^start_script$')],
        states={
            API_ID: [MessageHandler(Filters.text & ~Filters.command, api_id)],
            API_HASH: [MessageHandler(Filters.text & ~Filters.command, api_hash)],
            PHONE: [MessageHandler(Filters.text & ~Filters.command, phone)],
            CHANNEL: [MessageHandler(Filters.text & ~Filters.command, channel)],
            ADMIN_ID: [MessageHandler(Filters.text & ~Filters.command, admin_id)],
            AUTH_CODE: [MessageHandler(Filters.text & ~Filters.command, auth_code)],
        },
        fallbacks=[CommandHandler('cancel', cancel)],
    )

    updater.dispatcher.add_handler(CommandHandler('start', start))
    updater.dispatcher.add_handler(conv_handler)
    updater.dispatcher.add_handler(CommandHandler('auto_on', auto_on))
    updater.dispatcher.add_handler(CommandHandler('auto_off', auto_off))
    updater.dispatcher.add_handler(CommandHandler('set_reply', set_reply))
    updater.dispatcher.add_handler(CommandHandler('keep_on', keep_on))
    updater.dispatcher.add_handler(CommandHandler('keep_off', keep_off))
    updater.dispatcher.add_handler(CommandHandler('help', help_command))

    updater.start_polling()
    updater.idle()

if __name__ == '__main__':
    main()
