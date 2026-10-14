<?php

use App\Http\Controllers\Admin\PerfilController;
use App\Http\Controllers\Admin\TokenController;
use App\Http\Controllers\Admin\VideoAdminController;
use App\Http\Controllers\Auth\LoginController;
use App\Http\Controllers\PublicVideoController;
use Illuminate\Support\Facades\Route;

// Con route() y no Route::redirect('/', '/admin'): así respeta la subcarpeta (jmarreros.com/mis-looms).
Route::get('/', fn () => redirect()->route('admin.videos.index'));

// Página pública para compartir.
Route::get('/v/{slug}', [PublicVideoController::class, 'show'])
    ->where('slug', '[a-z0-9]+')
    ->name('video.ver');

// Acceso al panel (un solo usuario).
Route::middleware('guest')->group(function () {
    Route::get('/login', [LoginController::class, 'formulario'])->name('login');
    Route::post('/login', [LoginController::class, 'entrar'])->middleware('throttle:5,1');
});
Route::post('/logout', [LoginController::class, 'salir'])->middleware('auth')->name('logout');

// Panel de administración.
Route::middleware('auth')->prefix('admin')->name('admin.')->group(function () {
    Route::get('/', [VideoAdminController::class, 'index'])->name('videos.index');
    Route::get('/videos/{video:slug}', [VideoAdminController::class, 'show'])->name('videos.show');
    Route::patch('/videos/{video:slug}', [VideoAdminController::class, 'update'])->name('videos.update');
    Route::delete('/videos/{video:slug}', [VideoAdminController::class, 'destroy'])->name('videos.destroy');
    Route::get('/perfil', [PerfilController::class, 'show'])->name('perfil');
    Route::patch('/perfil', [PerfilController::class, 'actualizar'])->name('perfil.actualizar');
    Route::put('/perfil/password', [PerfilController::class, 'cambiarPassword'])->name('perfil.password');
    Route::get('/token', [TokenController::class, 'show'])->name('token');
    Route::post('/token', [TokenController::class, 'regenerar'])->name('token.regenerar');
});
