<?php

namespace App\Models;

use App\Services\VideoStorage;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;

class Video extends Model
{
    public const SUBIENDO = 'uploading';
    public const LISTO = 'ready';
    public const FALLIDO = 'failed';

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'size' => 'integer',
            'duration' => 'float',
            'views' => 'integer',
        ];
    }

    public function getRouteKeyName(): string
    {
        return 'slug';
    }

    /** Slug corto de 12 caracteres aleatorios (a-z0-9): no adivinable, apto para la URL pública. */
    public static function nuevoSlug(): string
    {
        do {
            $slug = Str::lower(Str::random(12));
        } while (static::where('slug', $slug)->exists());

        return $slug;
    }

    public function estaListo(): bool
    {
        return $this->status === self::LISTO;
    }

    public function scopeListos(Builder $query): Builder
    {
        return $query->where('status', self::LISTO);
    }

    public function urlCompartir(): string
    {
        return route('video.ver', $this->slug);
    }

    public function urlVideo(): string
    {
        return app(VideoStorage::class)->urlPublica($this->s3_key);
    }

    public function urlMiniatura(): ?string
    {
        return $this->thumbnail_key
            ? app(VideoStorage::class)->urlPublica($this->thumbnail_key)
            : null;
    }

    public function titulo(): string
    {
        return $this->title ?: 'Video del '.$this->created_at->format('d/m/Y H:i');
    }

    public function duracionLegible(): string
    {
        if ($this->duration === null) {
            return '—';
        }
        $s = (int) round($this->duration);

        return $s >= 3600
            ? sprintf('%d:%02d:%02d', intdiv($s, 3600), intdiv($s % 3600, 60), $s % 60)
            : sprintf('%d:%02d', intdiv($s, 60), $s % 60);
    }

    public function tamanoLegible(): string
    {
        if ($this->size === null) {
            return '—';
        }
        $unidades = ['B', 'KB', 'MB', 'GB'];
        $v = (float) $this->size;
        $i = 0;
        while ($v >= 1024 && $i < count($unidades) - 1) {
            $v /= 1024;
            $i++;
        }

        return number_format($v, $i === 0 ? 0 : 1).' '.$unidades[$i];
    }

    /** Borra el video de S3 (objeto, miniatura o multipart pendiente) y el registro. */
    public function eliminarCompleto(VideoStorage $almacen): void
    {
        if ($this->status === self::SUBIENDO && $this->upload_id) {
            $almacen->abortarMultipart($this->s3_key, $this->upload_id);
        }
        // deleteObject no falla si el objeto no existe, así que es seguro en cualquier estado.
        $almacen->borrar($this->s3_key);
        if ($this->thumbnail_key) {
            $almacen->borrar($this->thumbnail_key);
        }
        $this->delete();
    }

    /** Datos que devuelve la API. */
    public function paraApi(): array
    {
        return [
            'slug' => $this->slug,
            'title' => $this->title,
            'status' => $this->status,
            'share_url' => $this->urlCompartir(),
            'video_url' => $this->urlVideo(),
            'thumbnail_url' => $this->urlMiniatura(),
            'size' => $this->size,
            'duration' => $this->duration,
            'width' => $this->width,
            'height' => $this->height,
            'views' => $this->views,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
