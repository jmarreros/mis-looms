<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Video;
use App\Services\VideoStorage;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;

class VideoAdminController extends Controller
{
    public function index(Request $request)
    {
        $busqueda = trim((string) $request->query('q', ''));

        $videos = Video::query()
            ->when($busqueda !== '', fn ($q) => $q->where(function ($q) use ($busqueda) {
                $q->where('title', 'like', "%$busqueda%")->orWhere('slug', 'like', "%$busqueda%");
            }))
            ->latest()
            ->paginate(12)
            ->withQueryString();

        // Tras borrar el último video de una página, esa página queda vacía: ir a la última que exista.
        if ($videos->isEmpty() && $videos->currentPage() > 1) {
            return redirect()->route('admin.videos.index', array_filter([
                'q' => $busqueda,
                'page' => $videos->lastPage() > 1 ? $videos->lastPage() : null,
            ]));
        }

        return view('admin.videos', ['videos' => $videos, 'busqueda' => $busqueda, 'total' => Video::count()]);
    }

    public function show(Video $video)
    {
        return view('admin.video', ['video' => $video]);
    }

    public function update(Request $request, Video $video): RedirectResponse
    {
        $datos = $request->validate(['title' => ['nullable', 'string', 'max:255']]);
        $video->update(['title' => $datos['title'] ?: null]);

        return back()->with('estado', 'Título actualizado.');
    }

    public function destroy(Request $request, Video $video, VideoStorage $almacen): RedirectResponse
    {
        $video->eliminarCompleto($almacen);

        // Desde el detalle, esa página ya no existe: ir al listado. Desde el listado, volver a la
        // misma página y búsqueda.
        $destino = $request->boolean('desde_detalle') ? redirect()->route('admin.videos.index') : back();

        return $destino->with('estado', 'Video eliminado.');
    }
}
