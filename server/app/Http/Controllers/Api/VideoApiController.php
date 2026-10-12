<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Video;
use App\Services\VideoStorage;
use Aws\Exception\AwsException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

/**
 * Contrato con las apps nativas: crear → subir partes directo a S3 → completar → miniatura.
 * Ver docs/api.md.
 */
class VideoApiController extends Controller
{
    public function __construct(private VideoStorage $almacen) {}

    /** POST /api/videos — crea el registro, inicia el multipart y firma todas las partes. */
    public function store(Request $request): JsonResponse
    {
        $datos = $request->validate([
            'size' => ['required', 'integer', 'min:1'],
            'title' => ['nullable', 'string', 'max:255'],
            'duration' => ['nullable', 'numeric', 'min:0'],
            'width' => ['nullable', 'integer', 'min:1'],
            'height' => ['nullable', 'integer', 'min:1'],
        ]);

        $tamanoParte = config('mislooms.part_size');
        $partes = (int) ceil($datos['size'] / $tamanoParte);
        if ($partes > config('mislooms.max_parts')) {
            throw ValidationException::withMessages(['size' => 'El video es demasiado grande.']);
        }

        $slug = Video::nuevoSlug();
        $key = config('mislooms.video_prefix').$slug.'.mp4';
        $uploadId = $this->almacen->iniciarMultipart($key, 'video/mp4');

        $video = Video::create([
            'slug' => $slug,
            'title' => $datos['title'] ?? null,
            's3_key' => $key,
            'upload_id' => $uploadId,
            'size' => $datos['size'],
            'duration' => $datos['duration'] ?? null,
            'width' => $datos['width'] ?? null,
            'height' => $datos['height'] ?? null,
            'status' => Video::SUBIENDO,
            'views' => 0,
        ]);

        return response()->json([
            'video' => $video->paraApi(),
            'upload_id' => $uploadId,
            'part_size' => $tamanoParte,
            'parts' => $this->firmarPartes($video, range(1, $partes)),
        ], 201);
    }

    /** POST /api/videos/{slug}/parts — vuelve a firmar partes (URLs caducadas o subida reanudada). */
    public function parts(Request $request, Video $video): JsonResponse
    {
        $this->exigirSubiendo($video);
        $datos = $request->validate([
            'parts' => ['required', 'array', 'min:1', 'max:'.config('mislooms.max_parts')],
            'parts.*' => ['integer', 'min:1', 'max:'.config('mislooms.max_parts')],
        ]);

        return response()->json(['parts' => $this->firmarPartes($video, $datos['parts'])]);
    }

    /** POST /api/videos/{slug}/complete — une las partes y deja el video listo. */
    public function complete(Request $request, Video $video): JsonResponse
    {
        $this->exigirSubiendo($video);
        $datos = $request->validate([
            'parts' => ['required', 'array', 'min:1'],
            'parts.*.part_number' => ['required', 'integer', 'min:1'],
            'parts.*.etag' => ['required', 'string'],
            'duration' => ['nullable', 'numeric', 'min:0'],
            'width' => ['nullable', 'integer', 'min:1'],
            'height' => ['nullable', 'integer', 'min:1'],
            'has_thumbnail' => ['nullable', 'boolean'],
        ]);

        $partes = collect($datos['parts'])
            ->map(fn ($p) => ['PartNumber' => (int) $p['part_number'], 'ETag' => $p['etag']])
            ->sortBy('PartNumber')
            ->values()
            ->all();

        try {
            $this->almacen->completarMultipart($video->s3_key, $video->upload_id, $partes);
        } catch (AwsException $e) {
            // La subida sigue abierta: la app puede corregir las partes y reintentar.
            return response()->json([
                'message' => 'S3 no pudo completar la subida: '.$e->getAwsErrorMessage(),
            ], 502);
        }

        $video->update([
            'status' => Video::LISTO,
            'upload_id' => null,
            'size' => $this->almacen->tamano($video->s3_key) ?? $video->size,
            'duration' => $datos['duration'] ?? $video->duration,
            'width' => $datos['width'] ?? $video->width,
            'height' => $datos['height'] ?? $video->height,
            'thumbnail_key' => ($datos['has_thumbnail'] ?? false)
                ? config('mislooms.thumb_prefix').$video->slug.'.jpg'
                : null,
        ]);

        return response()->json(['video' => $video->paraApi()]);
    }

    /** POST /api/videos/{slug}/thumbnail — URL prefirmada para subir la miniatura JPG. */
    public function thumbnail(Video $video): JsonResponse
    {
        abort_if($video->status === Video::FALLIDO, 409, 'El video falló.');

        $key = config('mislooms.thumb_prefix').$video->slug.'.jpg';

        return response()->json([
            'upload_url' => $this->almacen->urlSubida($key, 'image/jpeg'),
            // Se firma con este Content-Type: la app debe enviarlo tal cual en el PUT.
            'headers' => ['Content-Type' => 'image/jpeg'],
        ]);
    }

    /** POST /api/videos/{slug}/abort — cancela una subida en curso. */
    public function abort(Video $video): JsonResponse
    {
        $this->exigirSubiendo($video);
        $this->almacen->abortarMultipart($video->s3_key, $video->upload_id);
        $video->update(['status' => Video::FALLIDO, 'upload_id' => null]);

        return response()->json(['video' => $video->paraApi()]);
    }

    /** @param  iterable<int>  $numeros */
    private function firmarPartes(Video $video, iterable $numeros): array
    {
        $partes = [];
        foreach ($numeros as $n) {
            $partes[] = [
                'part_number' => (int) $n,
                'url' => $this->almacen->urlParte($video->s3_key, $video->upload_id, (int) $n),
            ];
        }

        return $partes;
    }

    private function exigirSubiendo(Video $video): void
    {
        abort_unless(
            $video->status === Video::SUBIENDO && $video->upload_id,
            409,
            'La subida de este video ya no está en curso.'
        );
    }
}
