<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Cron de cPanel: * * * * * php /ruta/server/artisan schedule:run
Schedule::command('mislooms:limpiar-subidas')->hourly();
