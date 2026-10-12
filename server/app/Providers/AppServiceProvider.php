<?php

namespace App\Providers;

use App\Services\S3VideoStorage;
use App\Services\VideoStorage;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        $this->app->singleton(VideoStorage::class, fn () => new S3VideoStorage(config('mislooms')));
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        //
    }
}
