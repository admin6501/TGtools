<?php

$botToken = "7371315768:AAHWbQyEzZGb8NixdHde5KzOEXRb4nHUmJg";
$apiUrl = "https://api.telegram.org/bot$botToken/";
$adminId = "1429423697"; // آیدی چت ادمین
$botActive = true; // وضعیت ربات (فعال یا غیرفعال)

// دریافت ورودی‌ها از وبهوک
$update = json_decode(file_get_contents('php://input'), TRUE);

$chat_id = $update['message']['chat']['id'];
$text = $update['message']['text'];

// تابع ارسال پیام
function sendMessage($chat_id, $text, $replyMarkup = null) {
    global $apiUrl;
    $url = $apiUrl . "sendMessage?chat_id=$chat_id&text=" . urlencode($text);

    if ($replyMarkup) {
        $url .= "&reply_markup=" . $replyMarkup;
    }

    file_get_contents($url);
}

// بررسی وضعیت فعال بودن ربات
if (!$botActive && $chat_id != $adminId) {
    sendMessage($chat_id, "ربات در حال حاضر غیرفعال است.");
    exit;
}

// تابع ارسال منوی اصلی
function sendMainMenu($chat_id) {
    global $apiUrl;
    $keyboard = [
        'keyboard' => [
            [['text' => 'ارسال نظر']]
        ],
        'resize_keyboard' => true,
        'one_time_keyboard' => false
    ];
    $encodedKeyboard = json_encode($keyboard);
    sendMessage($chat_id, 'لطفاً دکمه ارسال نظر را انتخاب کنید.', $encodedKeyboard);
}

if ($text == '/start' || $text == 'لغو') {
    sendMainMenu($chat_id);
} elseif ($text == 'ارسال نظر') {
    $keyboard = [
        'keyboard' => [
            [['text' => 'لغو']]
        ],
        'resize_keyboard' => true,
        'one_time_keyboard' => false
    ];
    $encodedKeyboard = json_encode($keyboard);
    sendMessage($chat_id, 'لطفاً نظر خود را ارسال کنید. برای لغو، دکمه لغو را فشار دهید.', $encodedKeyboard);
} elseif ($text == '/on' && $chat_id == $adminId) {
    $botActive = true;
    sendMessage($chat_id, 'ربات فعال شد.');
} elseif ($text == '/off' && $chat_id == $adminId) {
    $botActive = false;
    sendMessage($chat_id, 'ربات غیرفعال شد.');
} else {
    // ارسال بازخورد به ادمین
    $feedback = "کاربر: $chat_id\n\nپیام:\n$text";
    sendMessage($adminId, $feedback);
    sendMessage($chat_id, 'سپاس از شما برای ارسال بازخورد!');
}

?>
