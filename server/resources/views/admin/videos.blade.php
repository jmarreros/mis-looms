@extends('layouts.admin')
@section('titulo', 'Videos')

@section('contenido')
    <h1>Videos</h1>

    <form class="buscador" method="GET" action="{{ route('admin.videos.index') }}">
        <input type="search" name="q" value="{{ $busqueda }}" placeholder="Buscar por título o código">
        <button type="submit">Buscar</button>
    </form>

    @if ($videos->isEmpty())
        <p class="vacio">{{ $busqueda !== '' ? 'No hay videos que coincidan.' : 'Todavía no has subido ningún video.' }}</p>
    @else
        <div class="rejilla">
            @foreach ($videos as $video)
                <article class="video">
                    <div class="miniatura" @if ($video->urlMiniatura()) style="background-image:url('{{ $video->urlMiniatura() }}')" @endif>
                        @unless ($video->urlMiniatura()) Sin miniatura @endunless
                    </div>
                    <div class="cuerpo">
                        <h2>{{ $video->titulo() }}</h2>
                        <div class="meta">
                            <span class="insignia {{ $video->status }}">
                                {{ ['ready' => 'Listo', 'uploading' => 'Subiendo', 'failed' => 'Fallido'][$video->status] ?? $video->status }}
                            </span>
                            · {{ $video->duracionLegible() }} · {{ $video->tamanoLegible() }}
                            · {{ $video->views }} {{ $video->views === 1 ? 'vista' : 'vistas' }}
                            · {{ $video->created_at->format('d/m/Y H:i') }}
                        </div>
                        <div class="acciones">
                            @if ($video->estaListo())
                                <a class="boton" href="{{ $video->urlCompartir() }}" target="_blank" rel="noopener">Abrir</a>
                                <button type="button" data-copiar="{{ $video->urlCompartir() }}">Copiar enlace</button>
                            @endif
                            <form method="POST" action="{{ route('admin.videos.destroy', $video) }}"
                                  onsubmit="return confirm('¿Eliminar este video? Se borrará también de S3.')">
                                @csrf @method('DELETE')
                                <button class="peligro" type="submit">Eliminar</button>
                            </form>
                        </div>
                        <details class="renombrar">
                            <summary class="meta">Renombrar</summary>
                            <form method="POST" action="{{ route('admin.videos.update', $video) }}">
                                @csrf @method('PATCH')
                                <input type="text" name="title" value="{{ $video->title }}" maxlength="255" placeholder="Título">
                                <button type="submit">Guardar</button>
                            </form>
                        </details>
                    </div>
                </article>
            @endforeach
        </div>

        {{ $videos->links('pagination.mislooms') }}
    @endif

    <script>
        document.querySelectorAll('[data-copiar]').forEach(function (boton) {
            boton.addEventListener('click', function () {
                navigator.clipboard.writeText(boton.dataset.copiar).then(function () {
                    var texto = boton.textContent;
                    boton.textContent = '¡Copiado!';
                    setTimeout(function () { boton.textContent = texto; }, 1500);
                });
            });
        });
    </script>
@endsection
