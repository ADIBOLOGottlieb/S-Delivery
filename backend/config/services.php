<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Resend, Postmark, AWS, and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    // Notifications push Firebase (JSON du compte de service, de préférence encodé en base64).
    'fcm' => [
        'credentials' => env('FIREBASE_CREDENTIALS'),
    ],

    // Secret attendu dans l'en-tête X-Cron-Key de POST /api/v1/cron/run.
    'cron' => [
        'secret' => env('CRON_SECRET'),
    ],

    // Lien de téléchargement de l'app, envoyé aux clients avec leurs identifiants.
    'apk' => [
        'url' => env('APK_URL', 'https://github.com/ADIBOLOGottlieb/S-Delivery/releases/latest/download/s-delivery.apk'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

];
