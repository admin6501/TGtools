from telegram import Update
from telegram.ext import Updater, CommandHandler, MessageHandler, Filters, CallbackContext
import os

def get_user_input(prompt):
    return input(prompt)

# دریافت توکن و آی‌دی ادمین از کاربر
TOKEN = get_user_input("لطفاً توکن ربات تلگرام خود را وارد کنید: ")
ADMIN_CHAT_ID = get_user_input("لطفاً آی‌دی چت ادمین را وارد کنید: ")

# تابع استارت
def start(update: Update, context: CallbackContext) -> None:
    user = update.effective_user
    update.message.reply_text(f'سلام {user.first_name} عزیز! لطفاً پیشنهادات، انتقادات و نظرات خود را در مورد فروش فیلترشکن Config Master ارسال کنید.')

# تابع دریافت پیام کاربران
def handle_message(update: Update, context: CallbackContext) -> None:
    user = update.effective_user
    message = update.message.text
    user_id = user.id
    username = user.username
    admin_message = f'پیام جدید از {username} (ID: {user_id}):\n\n"{message}"'
    
    # ارسال پیام به ادمین
    context.bot.send_message(chat_id=ADMIN_CHAT_ID, text=admin_message)
    
    # ارسال پیام تایید به کاربر
    update.message.reply_text('پیام شما دریافت شد. از پیشنهادات شما متشکریم!')

def main() -> None:
    # ایجاد آپدیتر و دریافت دیسپچر
    updater = Updater(TOKEN)

    dispatcher = updater.dispatcher

    # اضافه کردن هندلرهای فرمان و پیام
    dispatcher.add_handler(CommandHandler("start", start))
    dispatcher.add_handler(MessageHandler(Filters.text & ~Filters.command, handle_message))

    # شروع ربات
    updater.start_polling()
    updater.idle()

if __name__ == '__main__':
    main()
