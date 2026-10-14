<?php

namespace App\Http\Controllers;

use App\Models\Video;
use App\Mail\PrimeraVisita;
use App\Models\User;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Mail;

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

        // El UPDATE condicionado es atómico: solo una petición pasa de 0 a 1 visitas y envía el aviso.
        $primera = Video::whereKey($video->id)->where('views', 0)->update(['views' => 1]) === 1;
        if ($primera) {
            $this->avisarPrimeraVisita($video);
        } else {
            $video->increment('views');
        }

        return view('publico.video', ['video' => $video]);
    }

    /** Avisa al administrador por correo; un fallo de envío no debe romper la página pública. */
    private function avisarPrimeraVisita(Video $video): void
    {
        $destino = User::orderBy('id')->value('email');
        if (! $destino) {
            return;
        }
        try {
            Mail::to($destino)->send(new PrimeraVisita($video));
        } catch (\Throwable $e) {
            report($e);
        }
    }
}
