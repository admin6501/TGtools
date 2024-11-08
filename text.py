import os
from telethon import TelegramClient, events
from gtts import gTTS
import fitz  # PyMuPDF
import docx
import pytesseract
from PIL import Image

# دریافت اطلاعات حساب کاربری تلگرام از کاربر
api_id = input("Please enter your API ID: ")
api_hash = input("Please enter your API Hash: ")
bot_token = input("Please enter your Bot Token: ")

# ایجاد کلاینت تلگرام
client = TelegramClient('bot', api_id, api_hash).start(bot_token=bot_token)

# تابع برای تبدیل متن به صوت
def text_to_speech(text, file_name):
    tts = gTTS(text=text, lang='fa')
    tts.save(file_name)
    return file_name

# تابع برای تبدیل PDF به متن
def pdf_to_text(file_path):
    doc = fitz.open(file_path)
    text = ""
    for page in doc:
        text += page.get_text()
    return text

# تابع برای تبدیل Word به متن
def word_to_text(file_path):
    doc = docx.Document(file_path)
    text = ""
    for para in doc.paragraphs:
        text += para.text + "\n"
    return text

# تابع برای تبدیل عکس به متن
def image_to_text(file_path):
    img = Image.open(file_path)
    text = pytesseract.image_to_string(img, lang='fas')
    return text

# هندلر برای دریافت پیام‌ها
@client.on(events.NewMessage(pattern='/start'))
async def start(event):
    await event.respond('به ربات تبدیل متن به صوت خوش آمدید! یک فایل PDF، Word، متن یا عکس بفرستید تا آن را به صوت تبدیل کنم.')

@client.on(events.NewMessage)
async def handle_message(event):
    if event.message.file:
        file = await event.message.download_media()
        file_name, file_extension = os.path.splitext(file)
        
        if file_extension in ['.pdf', '.docx', '.txt', '.png', '.jpg', '.jpeg']:
            if file_extension == '.pdf':
                text = pdf_to_text(file)
            elif file_extension == '.docx':
                text = word_to_text(file)
            elif file_extension == '.txt':
                with open(file, 'r', encoding='utf-8') as f:
                    text = f.read()
            elif file_extension in ['.png', '.jpg', '.jpeg']:
                text = image_to_text(file)
            
            speech_file = text_to_speech(text, file_name + '.mp3')
            await event.respond('اینجا فایل صوتی شما است:', file=speech_file)
            os.remove(speech_file)
        else:
            await event.respond('فرمت فایل پشتیبانی نمی‌شود. لطفاً یک فایل PDF، Word، متن یا عکس بفرستید.')
        os.remove(file)

print("Bot is running...")
client.run_until_disconnected()
