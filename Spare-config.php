<?php

$botToken = "8148198943:AAH-LQMhtE4S2QVzyQeZqKR5b1WYfyhUydA";
$apiUrl = "https://api.telegram.org/bot$botToken/";

$adminId = "1429423697";

$update = json_decode(file_get_contents('php://input'), TRUE);

$chat_id = $update['message']['chat']['id'];
$text = $update['message']['text'];

function sendMessage($chat_id, $text, $replyMarkup = null) {
    global $apiUrl;
    $url = $apiUrl . "sendMessage?chat_id=$chat_id&text=" . urlencode($text);

    if ($replyMarkup) {
        $url .= "&reply_markup=" . $replyMarkup;
    }

    file_get_contents($url);
}

function sendMainMenu($chat_id) {
    $keyboard = [
        'keyboard' => [
            [['text' => 'درخواست کانفیگ زاپاس']]
        ],
        'resize_keyboard' => true,
        'one_time_keyboard' => false
    ];
    $encodedKeyboard = json_encode($keyboard);
    sendMessage($chat_id, 'لطفاً یک گزینه را انتخاب کنید:', $encodedKeyboard);
}

function askLocation($chat_id) {
    $keyboard = [
        'keyboard' => [
            [['text' => 'آلمان'], ['text' => 'فرانسه']],
            [['text' => 'هلند'], ['text' => 'اسپانیا']],
            [['text' => 'انگلیس'], ['text' => 'سوئد']],
            [['text' => 'اسرائیل']]
        ],
        'resize_keyboard' => true,
        'one_time_keyboard' => false
    ];
    $encodedKeyboard = json_encode($keyboard);
    sendMessage($chat_id, 'کانفیگی که شما از ربات خریداری کرده‌اید از چه لوکیشن می‌باشد؟', $encodedKeyboard);
}

function askConfigName($chat_id) {
    sendMessage($chat_id, 'نام کانفیگ خریداری شده خود را وارد کنید:');
}

function askSpareLocation($chat_id) {
    $keyboard = [
        'keyboard' => [
            [['text' => 'آلمان'], ['text' => 'فرانسه']],
            [['text' => 'هلند'], ['text' => 'اسپانیا']],
            [['text' => 'انگلیس'], ['text' => 'سوئد']],
            [['text' => 'اسرائیل']]
        ],
        'resize_keyboard' => true,
        'one_time_keyboard' => false
    ];
    $encodedKeyboard = json_encode($keyboard);
    sendMessage($chat_id, 'کد کانفیگ زاپاس را از کدام لوکیشن می‌خواهید دریافت کنید؟', $encodedKeyboard);
}

function sendAdminRequest($chat_id, $location, $configName, $spareLocation) {
    global $adminId;
    $message = "درخواست جدید از کاربر $chat_id:\n\n";
    $message .= "لوکیشن کانفیگ خریداری شده: $location\n";
    $message .= "نام کانفیگ خریداری شده: $configName\n";
    $message .= "لوکیشن زاپاس مورد نظر: $spareLocation\n";
    sendMessage($adminId, $message);

    $keyboard = [
        'inline_keyboard' => [
            [['text' => 'ارسال لینک کانفیگ زاپاس', 'callback_data' => 'send_spare_config_link_' . $chat_id]]
        ]
    ];
    $encodedKeyboard = json_encode($keyboard);
    sendMessage($adminId, 'کاربر جدید درخواست کانفیگ زاپاس داده است.', $encodedKeyboard);
    sendMessage($chat_id, 'درخواست شما ثبت شد. به زودی بررسی خواهد شد.');
}

if ($text == '/start') {
    sendMainMenu($chat_id);
} elseif ($text == 'درخواست کانفیگ زاپاس') {
    askLocation($chat_id);
} elseif (in_array($text, ['آلمان', 'فرانسه', 'هلند', 'اسپانیا', 'انگلیس', 'سوئد', 'اسرائیل'])) {
    askConfigName($chat_id);
    $location = $text;
} elseif (isset($location) && empty($configName)) {
    askSpareLocation($chat_id);
    $configName = $text;
} elseif (isset($configName)) {
    $spareLocation = $text;
    sendAdminRequest($chat_id, $location, $configName, $spareLocation);
} else {
    sendMessage($chat_id, 'دستور نامعتبر. لطفاً دوباره تلاش کنید.');
}

?>
