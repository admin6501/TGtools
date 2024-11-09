import fitz  # PyMuPDF برای خواندن PDF
from telegram import Update, ReplyKeyboardMarkup
from telegram.ext import Updater, CommandHandler, MessageHandler, Filters, CallbackContext, ConversationHandler
from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

# دریافت توکن ربات از کاربر به زبان انگلیسی
TOKEN = input("Please enter your Telegram bot token: ")

# مراحل مکالمه
LANG, TEXT, FORMAT, FONT_SIZE, FONT_STYLE, FONT_BOLD_ITALIC, EDIT = range(7)

# متغیر برای ذخیره زبان ربات
bot_language = 'en'

# تابع تغییر زبان
def set_language(update: Update, context: CallbackContext) -> int:
    global bot_language
    bot_language = context.args[0] if context.args else 'en'
    lang_message = "زبان به فارسی تغییر یافت." if bot_language == 'fa' else "Language set to English."
    update.message.reply_text(lang_message)
    return start(update, context)

def get_language_text(en_text, fa_text):
    return fa_text if bot_language == 'fa' else en_text

def start(update: Update, context: CallbackContext) -> int:
    welcome_message = get_language_text(
        "Hello! Please send the text you want to convert to a file.\nTo cancel the conversation, enter /cancel.",
        "سلام! لطفاً متنی که می‌خواهید به فایل تبدیل شود را ارسال کنید.\nبرای لغو مکالمه، /cancel را وارد کنید."
    )
    update.message.reply_text(welcome_message)
    return TEXT

def get_text(update: Update, context: CallbackContext) -> int:
    context.user_data['text'] = update.message.text.split('\n')
    reply_keyboard = [['txt', 'docx', 'pdf']]
    format_message = get_language_text(
        "Text received. Please choose the output file format (txt, docx, or pdf):",
        "متن دریافت شد. لطفاً فرمت فایل خروجی را انتخاب کنید (txt, docx یا pdf):"
    )
    update.message.reply_text(format_message, reply_markup=ReplyKeyboardMarkup(reply_keyboard, one_time_keyboard=True))
    return FORMAT

def get_format(update: Update, context: CallbackContext) -> int:
    context.user_data['format'] = update.message.text.lower()
    if context.user_data['format'] == 'docx':
        font_size_message = get_language_text(
            "docx format selected. Please choose a font size between 10 and 20 (e.g., 12):",
            "فرمت docx انتخاب شد. لطفاً اندازه فونت را بین 10 و 20 انتخاب کنید (مثلاً 12):"
        )
        update.message.reply_text(font_size_message)
        return FONT_SIZE
    elif context.user_data['format'] == 'pdf':
        pdf_message = get_language_text(
            "PDF format selected. The text will be converted to a PDF file.",
            "فرمت PDF انتخاب شد. متن به فایل PDF تبدیل خواهد شد."
        )
        update.message.reply_text(pdf_message)
        convert_to_pdf(update, context)
        return ConversationHandler.END
    elif context.user_data['format'] == 'txt':
        txt_message = get_language_text(
            "txt format selected. A simple text file will be sent.",
            "فرمت txt انتخاب شد. یک فایل متنی ساده ارسال خواهد شد."
        )
        update.message.reply_text(txt_message)
        with open("text_output.txt", "w") as file:
            file.write("\n".join(context.user_data['text']))
        with open("text_output.txt", "rb") as file:
            update.message.reply_document(file)
        return ConversationHandler.END
    else:
        invalid_format_message = get_language_text(
            "Invalid format. Please choose one of txt, docx, or pdf.",
            "فرمت نامعتبر است. لطفاً یکی از فرمت‌های txt، docx یا pdf را انتخاب کنید."
        )
        update.message.reply_text(invalid_format_message)
        return FORMAT

def get_font_size(update: Update, context: CallbackContext) -> int:
    try:
        font_size = int(update.message.text)
        if 10 <= font_size <= 20:
            context.user_data['font_size'] = font_size
            reply_keyboard = [['Arial', 'Times New Roman', 'Calibri', 'B Nazanin', 'B Mitra', 'B Yekan']]
            font_style_message = get_language_text(
                "Font size received. Please choose a font style:",
                "اندازه فونت دریافت شد. لطفاً سبک فونت را انتخاب کنید:"
            )
            update.message.reply_text(font_style_message, reply_markup=ReplyKeyboardMarkup(reply_keyboard, one_time_keyboard=True))
            return FONT_STYLE
        else:
            size_error_message = get_language_text(
                "Please enter a number between 10 and 20.",
                "لطفاً عددی بین 10 و 20 وارد کنید."
            )
            update.message.reply_text(size_error_message)
            return FONT_SIZE
    except ValueError:
        size_error_message = get_language_text(
            "Please enter a valid number for font size.",
            "لطفاً یک عدد معتبر برای اندازه فونت وارد کنید."
        )
        update.message.reply_text(size_error_message)
        return FONT_SIZE

def get_font_style(update: Update, context: CallbackContext) -> int:
    context.user_data['font_style'] = update.message.text
    reply_keyboard = [['Bold', 'Italic', 'Bold & Italic', 'Normal']]
    font_weight_message = get_language_text(
        "Font style selected. Please choose a font weight (Bold, Italic, Bold & Italic, or Normal):",
        "سبک فونت انتخاب شد. لطفاً وزن فونت را انتخاب کنید (Bold، Italic، Bold & Italic یا Normal):"
    )
    update.message.reply_text(font_weight_message, reply_markup=ReplyKeyboardMarkup(reply_keyboard, one_time_keyboard=True))
    return FONT_BOLD_ITALIC

def get_font_bold_italic(update: Update, context: CallbackContext) -> int:
    style = update.message.text
    context.user_data['bold'] = 'Bold' in style
    context.user_data['italic'] = 'Italic' in style

    edit_message = get_language_text(
        "Do you want to edit the text? If yes, enter /edit. Otherwise, the file will be converted.",
        "آیا می‌خواهید متن را ویرایش کنید؟ اگر بله، /edit را وارد کنید. در غیر این صورت، فایل تبدیل خواهد شد."
    )
    update.message.reply_text(edit_message)
    return EDIT

def edit_text(update: Update, context: CallbackContext) -> int:
    edit_mode_message = get_language_text(
        "You are in edit mode.\nTo delete a line, use the command /delete followed by the line number (e.g., /delete 3).\nTo replace a word, use the command /replace followed by new_word old_word.\nTo add a new line, use /add followed by the text.\nTo finish and save changes, use /done.",
        "شما در حالت ویرایش هستید.\nبرای حذف یک خط، دستور /delete را به همراه شماره خط وارد کنید (مثلاً /delete 3).\nبرای جایگزینی یک کلمه، از دستور /replace به همراه new_word old_word استفاده کنید.\nبرای افزودن یک خط جدید، از /add به همراه متن استفاده کنید.\nبرای اتمام و ذخیره تغییرات، از /done استفاده کنید."
    )
    update.message.reply_text(edit_mode_message)
    return EDIT

def handle_edit_commands(update: Update, context: CallbackContext) -> int:
    command = update.message.text
    if command.startswith('/delete'):
        try:
            line_number = int(command.split()[1]) - 1
            if 0 <= line_number < len(context.user_data['text']):
                context.user_data['text'].pop(line_number)
                delete_message = get_language_text("Line deleted.", "خط حذف شد.")
                update.message.reply_text(delete_message)
            else:
                invalid_line_message = get_language_text("Invalid line number.", "شماره خط نامعتبر است.")
                update.message.reply_text(invalid_line_message)
        except (IndexError, ValueError):
            invalid_line_message = get_language_text("Please enter a valid line number.", "لطفاً یک شماره خط معتبر وارد کنید.")
            update.message.reply_text(invalid_line_message)
    
    elif command.startswith('/replace'):
        try:
            _, new_word, old_word = command.split()
            context.user_data['text'] = [line.replace(old_word, new_word) for line in context.user_data['text']]
            replace_message = get_language_text("Word replaced.", "کلمه جایگزین شد.")
            update.message.reply_text(replace_message)
        except ValueError:
            replace_error_message = get_language_text("Please enter the command as follows: /replace new_word old_word", "لطفاً دستور را به این صورت وارد کنید: /replace new_word old_word")
            update.message.reply_text(replace_error_message)

    elif command.startswith('/add'):
        new_line = command[5:]
        context.user_data['text'].append(new_line)
        add_message = get_language_text("New line added.", "خط جدید اضافه شد.")
        update.message.reply_text(add_message)

    elif command == '/done':
        if context.user_data['format'] == 'pdf':
            return convert_to_pdf(update, context)
        else:
            return convert_to_file(update, context
