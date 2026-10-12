<?php

return [
    'bucket' => env('AWS_BUCKET'),
    'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    'key' => env('AWS_ACCESS_KEY_ID'),
    'secret' => env('AWS_SECRET_ACCESS_KEY'),

    // URL pública del bucket (sin barra final). Si se usa CloudFront, poner aquí su dominio.
    'public_url' => env('MISLOOMS_PUBLIC_URL'),

    // Subida multipart directa a S3: tamaño de cada parte (S3 exige >= 5 MB salvo la última).
    'part_size' => 10 * 1024 * 1024,
    'max_parts' => 10000,

    // Vigencia de las URLs prefirmadas.
    'presign_minutes' => 60,

    // Una subida "uploading" sin completar tras estas horas se marca como fallida.
    'upload_timeout_hours' => 24,

    'video_prefix' => 'videos/',
    'thumb_prefix' => 'thumbs/',
];
