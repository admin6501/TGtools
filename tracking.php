<?php

$botToken = "7861812642:AAGrb-mGMZha42KEsjaclyQPEm1ViXSBU0c";
$apiUrl = "https://api.telegram.org/bot$botToken/";

$adminId = "1429423697";

$update = json_decode(file_get_contents('php://input'), TRUE);

$chat_id = $update['message']['chat']['id'];
$text = $update['message']['text'];
$callback_query = $update['callback_query'];

session_start();

if (!isset($_SESSION['messages'])) {
    $_SESSION['messages'] = [];
}

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
            [['text' => 'پیگیری سفارش']]
        ],
        'resize_keyboard' => true,
        'one_time_keyboard' => false
    ];
    $encodedKeyboard = json_encode($keyboard);
    sendMessage($chat_id, 'سلام! برای پیگیری سفارش لطفاً روی گزینه پیگیری سفارش کلیک کنید.', $encodedKeyboard);
}

function requestOrderDetails($chat_id) {
    $keyboard = [
        'keyboard' => [
            [['text' => 'انصراف و برگشت']]
        ],
        'resize_keyboard' => true,
        'one_time_keyboard' => false
    ];
    $encodedKeyboard = json_encode($keyboard);
    sendMessage($chat_id, 'لطفاً اطلاعات زیر را وارد کنید:\nپلن انتخابی، لوکیشن کانفیگ، دسته‌بندی انتخاب شده، مبلغ پرداختی', $encodedKeyboard);
}

function processOrderDetails($chat_id, $text) {
    global $adminId;

    // ذخیره پیام کاربر در سشن
    $_SESSION['messages'][] = ['from' => $chat_id, 'to' => $adminId, 'text' => $text, 'replied' => false];
    
    // ساخت دکمه‌های شیشه‌ای پاسخ و عدم نیاز به پاسخ
    $inline_keyboard = [
        'inline_keyboard' => [
            [['text' => 'ارسال پاسخ', 'callback_data' => 'reply_to_' . $chat_id]],
            [['text' => 'نیاز به ارسال پاسخ ندارم', 'callback_data' => 'no_reply_to_' . $chat_id]]
        ]
    ];
    $encodedInlineKeyboard = json_encode($inline_keyboard);
    
    sendMessage($adminId, "پیام جدید از کاربر $chat_id:\n$text", $encodedInlineKeyboard);
    sendMessage($chat_id, 'پیام شما دریافت شد. به زودی بررسی خواهد شد.');
    sendMainMenu($chat_id);
}

function sendAdminReply($userId, $replyText) {
    global $adminId;

    foreach ($_SESSION['messages'] as &$message) {
        if ($message['from'] == $userId && !$message['replied']) {
            $message['replied'] = true;
            sendMessage($userId, "پاسخ ادمین:\n$replyText");
            sendMessage($adminId, "پاسخ شما برای کاربر $userId ارسال شد:\n$replyText");
            break;
        }
    }
}

function noAdminReply($userId) {
    global $adminId;

    foreach ($_SESSION['messages'] as &$message) {
        if ($message['from'] == $userId && !$message['replied']) {
            $message['replied'] = true;
            sendMessage($adminId, "پاسخ شما برای کاربر $userId ارسال نشد.");
            break;
        }
    }
}

function processUserReply($chat_id, $text) {
    global $adminId;

    // ذخیره پاسخ کاربر در سشن
    $_SESSION['messages'][] = ['from' => $chat_id, 'to' => $adminId, 'text' => $text, 'replied' => false];
    
    // ساخت دکمه‌های شیشه‌ای پاسخ و عدم نیاز به پاسخ
    $inline_keyboard = [
        'inline_keyboard' => [
            [['text' => 'ارسال پاسخ', 'callback_data' => 'reply_to_' . $chat_id]],
            [['text' => 'نیاز به ارسال پاسخ ندارم', 'callback_data' => 'no_reply_to_' . $chat_id]]
        ]
    ];
    $encodedInlineKeyboard = json_encode($inline_keyboard);
    
    sendMessage($adminId, "پاسخ جدید از کاربر $chat_id:\n$text", $encodedInlineKeyboard);
    sendMessage($chat_id, 'پاسخ شما ارسال شد.');
}

if (isset($callback_query)) {
    $callback_data = $callback_query['data'];
    $callback_chat_id = $callback_query['message']['chat']['id'];
    $callback_message_id = $callback_query['message']['message_id'];

    if (strpos($callback_data, 'reply_to_') === 0) {
        $userId = str_replace('reply_to_', '', $callback_data);

        // ذخیره اطلاعات پاسخ برای ادمین
        $_SESSION['awaiting_reply'] = $userId;
        sendMessage($callback_chat_id, "لطفاً پیام خود را برای کاربر $userId وارد کنید:");
    } elseif (strpos($callback_data, 'no_reply_to_') === 0) {
        $userId = str_replace('no_reply_to_', '', $callback_data);

        noAdminReply($userId);
        sendMessage($callback_chat_id, "پاسخ شما ارسال نشد و پیام بدون پاسخ باقی ماند.");
    }
} elseif ($text == '/start') {
    sendMainMenu($chat_id);
} elseif ($text == 'پیگیری سفارش') {
    requestOrderDetails($chat_id);
} elseif ($text == 'انصراف و برگشت') {
    sendMainMenu($chat_id);
} elseif (preg_match("/^(پلن انتخابی|لوکیشن کانفیگ|دسته‌بندی انتخاب شده|مبلغ پرداختی):/", $text)) {
    processOrderDetails($chat_id, $text);
} elseif ($chat_id == $adminId && isset($_SESSION['awaiting_reply'])) {
    sendAdminReply($_SESSION['awaiting_reply'], $text);
    unset($_SESSION['awaiting_reply']);
} else {
    processUserReply($chat_id, $text);
}

?>
