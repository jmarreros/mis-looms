{{-- Miniatura de un video: la imagen subida por la app o, si no hay, un fondo de color estable según el slug. --}}
@php($imagen = $video->urlMiniatura())
<span @class(['miniatura', 'con-imagen' => $imagen, 'tono-'.(crc32($video->slug) % 3)])
      @if ($imagen) style="background-image: url('{{ $imagen }}')" @endif>
    <span class="play">@include('partials.icono', ['nombre' => 'play', 'tam' => 20, 'color' => 'var(--neutro-100)'])</span>
    @unless ($video->estaListo())
        <span class="estado {{ $video->status }}">{{ ['uploading' => 'Subiendo', 'failed' => 'Fallido'][$video->status] ?? $video->status }}</span>
    @endunless
    @if ($video->duration !== null)
        <span class="duracion">{{ $video->duracionLegible() }}</span>
    @endif
</span>
