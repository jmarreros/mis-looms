<?php

namespace App\Http\Controllers;

use App\Models\Video;
use App\Models\Vista;
use App\Mail\PrimeraVisita;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Mail;

class PublicVideoController extends Controller
{
    public function show(Request $request, string $slug)
    {
        $video = Video::listos()->where('slug', $slug)->firstOrFail();

        // El administrador con sesión abierta ve la misma pantalla que el detalle del panel (copiar el
        // enlace, renombrar, eliminar) y sus visitas no cuentan. Quien no tiene sesión ve la página pública.
        if (Auth::check()) {
            return view('admin.video', ['video' => $video, 'vistas' => $video->historialVistas()]);
        }

        $vista = $this->registrarVista($request, $video);

        // El UPDATE condicionado es atómico: solo una petición pasa de 0 a 1 visitas y envía el aviso.
        $primera = Video::whereKey($video->id)->where('views', 0)->update(['views' => 1]) === 1;
        if ($primera) {
            $video->views = 1; // el UPDATE no toca el modelo ya cargado, que es el que muestra la página
            $this->avisarPrimeraVisita($video, $vista);
        } else {
            $video->increment('views');
        }

        return view('publico.video', ['video' => $video]);
    }

    private function registrarVista(Request $request, Video $video): Vista
    {
        // El navegador envía el user agent a su antojo: limpiarlo y limitarlo antes de guardarlo.
        $agente = mb_substr(mb_scrub((string) $request->userAgent(), 'UTF-8'), 0, 1000);

        return $video->vistas()->create([
            'ip' => $request->ip(),
            'user_agent' => $agente !== '' ? $agente : null,
        ]);
    }

    /** Avisa al administrador por correo; un fallo de envío no debe romper la página pública. */
    private function avisarPrimeraVisita(Video $video, Vista $vista): void
    {
        $destino = User::orderBy('id')->value('email');
        if (! $destino) {
            return;
        }
        try {
            Mail::to($destino)->send(new PrimeraVisita($video, $vista));
        } catch (\Throwable $e) {
            report($e);
        }
    }
}
