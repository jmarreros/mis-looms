<?php

namespace App\Http\Controllers;

use App\Models\Video;
use Illuminate\Support\Facades\Auth;

class PublicVideoController extends Controller
{
    public function show(string $slug)
    {
        $video = Video::listos()->where('slug', $slug)->firstOrFail();

        // El administrador con sesión abierta ve la misma pantalla que el detalle del panel (copiar el
        // enlace, renombrar, eliminar) y sus visitas no cuentan. Quien no tiene sesión ve la página pública.
        if (Auth::check()) {
            return view('admin.video', ['video' => $video]);
        }

        $video->increment('views');

        return view('publico.video', ['video' => $video]);
    }
}
