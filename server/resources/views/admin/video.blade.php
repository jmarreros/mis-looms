@extends('layouts.admin')
@section('titulo', $video->titulo())

@section('contenido')
    <a class="boton discreto chico volver" href="{{ route('admin.videos.index') }}">@include('partials.icono', ['nombre' => 'atras']) Videos</a>

    <div class="detalle">
        <div class="columna-video">
            @if ($video->estaListo())
                <video class="reproductor" controls playsinline preload="metadata"
                       @if ($video->urlMiniatura()) poster="{{ $video->urlMiniatura() }}" @endif
                       src="{{ $video->urlVideo() }}"></video>
            @else
                @include('partials.miniatura', ['video' => $video])
            @endif
            <div class="titulo-pagina">
                <h1>{{ $video->titulo() }}</h1>
                <span class="suave">
                    Subido el {{ $video->created_at->translatedFormat('j M Y') }}
                    · {{ $video->views }} {{ $video->views === 1 ? 'vista' : 'vistas' }}
                </span>
            </div>
        </div>

        <aside class="lateral">
            @if ($video->estaListo())
                <div class="bloque">
                    <span class="rotulo">Enlace para compartir</span>
                    <div class="copiable">
                        <a class="valor" href="{{ $video->urlCompartir() }}" target="_blank" rel="noopener">{{ $video->urlCompartir() }}</a>
                        <button class="boton primario chico" type="button" data-copiar="{{ $video->urlCompartir() }}">Copiar</button>
                    </div>
                </div>
            @endif

            <form class="bloque" method="POST" action="{{ route('admin.videos.update', $video) }}">
                @csrf @method('PATCH')
                <label class="rotulo" for="titulo">Título</label>
                <div class="renombrar">
                    <input class="entrada" id="titulo" type="text" name="title" value="{{ $video->title }}" maxlength="255" placeholder="{{ $video->titulo() }}">
                    <button class="boton chico" type="submit" style="height: 44px">Guardar</button>
                </div>
            </form>

            <dl class="datos">
                <dt>Código</dt><dd class="mono">{{ $video->slug }}</dd>
                <dt>Estado</dt><dd>{{ ['ready' => 'Listo', 'uploading' => 'Subiendo', 'failed' => 'Fallido'][$video->status] ?? $video->status }}</dd>
                <dt>Duración</dt><dd>{{ $video->duracionLegible() }}</dd>
                <dt>Tamaño</dt><dd>{{ $video->tamanoLegible() }}</dd>
                <dt>Resolución</dt><dd>{{ $video->width && $video->height ? $video->width.' × '.$video->height : '—' }}</dd>
            </dl>

            <div class="acciones">
                @if ($video->estaListo())
                    <a class="boton" href="{{ $video->urlVideo() }}" download target="_blank" rel="noopener">@include('partials.icono', ['nombre' => 'descargar']) Descargar</a>
                @endif
                <button class="boton peligro" type="button" onclick="document.getElementById('confirmar-eliminar').showModal()">
                    @include('partials.icono', ['nombre' => 'eliminar']) Eliminar
                </button>
            </div>
        </aside>
    </div>

    <dialog class="confirmar" id="confirmar-eliminar">
        <h2>¿Eliminar este video?</h2>
        <p>“{{ $video->titulo() }}” se borrará para siempre (también de S3) y el enlace dejará de funcionar.</p>
        <div class="botones">
            <button class="boton" type="button" onclick="this.closest('dialog').close()">Cancelar</button>
            <form method="POST" action="{{ route('admin.videos.destroy', $video) }}">
                @csrf @method('DELETE')
                <button class="boton primario" type="submit">Eliminar</button>
            </form>
        </div>
    </dialog>
@endsection
