<?php

namespace App\Http\Controllers;

use App\Models\Video;
use Illuminate\Support\Facades\Auth;

class PublicVideoController extends Controller
{
    public function show(string $slug)
    {
        $video = Video::listos()->where('slug', $slug)->firstOrFail();

        // Las visitas del propio administrador (sesión abierta) no cuentan.
        if (! Auth::check()) {
            $video->increment('views');
        }

        return view('publico.video', ['video' => $video]);
    }
}
