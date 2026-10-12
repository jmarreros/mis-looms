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

        return view('admin.videos', ['videos' => $videos, 'busqueda' => $busqueda]);
    }

    public function update(Request $request, Video $video): RedirectResponse
    {
        $datos = $request->validate(['title' => ['nullable', 'string', 'max:255']]);
        $video->update(['title' => $datos['title'] ?: null]);

        return back()->with('estado', 'Título actualizado.');
    }

    public function destroy(Video $video, VideoStorage $almacen): RedirectResponse
    {
        $video->eliminarCompleto($almacen);

        return back()->with('estado', 'Video eliminado.');
    }
}
