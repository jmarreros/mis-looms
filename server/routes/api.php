<?php

use App\Http\Controllers\Api\VideoApiController;
use Illuminate\Support\Facades\Route;

// Token personal de Sanctum (se genera en el panel, sección "Token de la app").
Route::middleware('auth:sanctum')->group(function () {
    // Para el botón "Probar conexión" de las apps: 200 si el token es válido, 401 si no.
    Route::get('ping', fn () => response()->json(['ok' => true]));
});

Route::middleware('auth:sanctum')->prefix('videos')->group(function () {
    Route::post('/', [VideoApiController::class, 'store']);
    Route::post('{video:slug}/parts', [VideoApiController::class, 'parts']);
    Route::post('{video:slug}/complete', [VideoApiController::class, 'complete']);
    Route::post('{video:slug}/thumbnail', [VideoApiController::class, 'thumbnail']);
    Route::post('{video:slug}/abort', [VideoApiController::class, 'abort']);
});
