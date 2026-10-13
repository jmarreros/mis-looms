@extends('layouts.admin')
@section('titulo', 'Videos')

@section('contenido')
    <div class="titulo-pagina">
        <h1>Videos</h1>
        <span class="suave">
            @if ($total === 0)
                Sin videos
            @elseif ($busqueda !== '')
                {{ $videos->total() }} de {{ $total }} videos
            @else
                {{ $total }} {{ $total === 1 ? 'video' : 'videos' }}
            @endif
        </span>
    </div>

    @if ($total > 0)
        <form class="buscador" method="GET" action="{{ route('admin.videos.index') }}" role="search">
            @include('partials.icono', ['nombre' => 'buscar', 'tam' => 18, 'color' => 'var(--neutro-500)'])
            <input type="search" name="q" value="{{ $busqueda }}" placeholder="Buscar por título o código" aria-label="Buscar">
            @if ($busqueda !== '')
                <a class="boton discreto chico" href="{{ route('admin.videos.index') }}" style="background: var(--neutro-800)">Limpiar</a>
            @endif
        </form>
    @endif

    @if ($total === 0)
        <div class="vacio">
            <div class="vacio-dibujo"><span>@include('partials.icono', ['nombre' => 'play', 'tam' => 22, 'color' => 'var(--acento-500)'])</span></div>
            <div class="texto">
                <h2>Todavía no has subido ningún video.</h2>
                <p class="suave">Conecta la app de grabación con tu token y tus videos aparecerán aquí en cuanto termines de grabar.</p>
                <a class="boton primario" href="{{ route('admin.token') }}">Ver mi token</a>
            </div>
        </div>
    @elseif ($videos->isEmpty())
        <div class="sin-resultados">
            <div class="icono-circulo">@include('partials.icono', ['nombre' => 'buscar', 'tam' => 34, 'color' => 'var(--neutro-500)'])</div>
            <h2>Sin resultados para “{{ $busqueda }}”</h2>
            <p class="suave">Prueba con otra palabra del título o con el código del video.</p>
        </div>
    @else
        <div class="rejilla">
            @foreach ($videos as $video)
                <article class="tarjeta-video">
                    <a class="enlace-video" href="{{ route('admin.videos.show', $video) }}">
                        @include('partials.miniatura', ['video' => $video])
                        <span class="info">
                            <span class="titulo">{{ $video->titulo() }}</span>
                            <span class="meta">
                                <span class="codigo">{{ $video->slug }}</span>
                                {{ $video->created_at->translatedFormat('j M Y') }} · {{ $video->views }} {{ $video->views === 1 ? 'vista' : 'vistas' }}
                            </span>
                        </span>
                    </a>
                    <div class="acciones-tarjeta">
                        @if ($video->estaListo())
                            <button class="boton chico" type="button" data-copiar="{{ $video->urlCompartir() }}">
                                @include('partials.icono', ['nombre' => 'copiar', 'tam' => 15]) Copiar enlace
                            </button>
                        @endif
                        <button class="boton chico icono" type="button" title="Renombrar" aria-label="Renombrar"
                                data-renombrar data-url="{{ route('admin.videos.update', $video) }}"
                                data-titulo="{{ $video->title }}" data-sugerido="{{ $video->titulo() }}">
                            @include('partials.icono', ['nombre' => 'editar', 'tam' => 15])
                        </button>
                        <button class="boton chico icono peligro" type="button" title="Eliminar" aria-label="Eliminar"
                                data-eliminar data-url="{{ route('admin.videos.destroy', $video) }}"
                                data-titulo="{{ $video->titulo() }}">
                            @include('partials.icono', ['nombre' => 'eliminar', 'tam' => 15])
                        </button>
                    </div>
                </article>
            @endforeach
        </div>

        {{-- Un único diálogo de cada tipo para toda la lista: el script rellena su destino y su texto. --}}
        <dialog class="confirmar" id="dialogo-renombrar">
            <form method="POST" action="">
                @csrf @method('PATCH')
                <h2>Renombrar video</h2>
                <input class="entrada" type="text" name="title" maxlength="255" aria-label="Título">
                <p class="suave" style="font-size: 14px; margin-top: 10px">Déjalo vacío para volver al título automático.</p>
                <div class="botones">
                    <button class="boton" type="button" data-cerrar>Cancelar</button>
                    <button class="boton primario" type="submit">Guardar</button>
                </div>
            </form>
        </dialog>

        <dialog class="confirmar" id="dialogo-eliminar">
            <form method="POST" action="">
                @csrf @method('DELETE')
                <h2>¿Eliminar este video?</h2>
                <p>“<span data-titulo></span>” se borrará para siempre (también de S3) y el enlace dejará de funcionar.</p>
                <div class="botones">
                    <button class="boton" type="button" data-cerrar>Cancelar</button>
                    <button class="boton primario" type="submit">Eliminar</button>
                </div>
            </form>
        </dialog>

        {{ $videos->links('pagination.mislooms') }}
    @endif

@push('scripts')
    <script>
        // Renombrar y eliminar: rellenan el diálogo compartido con el video de la tarjeta pulsada.
        (function () {
            var renombrar = document.getElementById('dialogo-renombrar');
            var eliminar = document.getElementById('dialogo-eliminar');
            if (!renombrar || !eliminar) return;

            document.querySelectorAll('[data-renombrar]').forEach(function (boton) {
                boton.addEventListener('click', function () {
                    var campo = renombrar.querySelector('input[name=title]');
                    renombrar.querySelector('form').action = boton.dataset.url;
                    campo.value = boton.dataset.titulo;
                    campo.placeholder = boton.dataset.sugerido;
                    renombrar.showModal();
                    campo.select();
                });
            });
            document.querySelectorAll('[data-eliminar]').forEach(function (boton) {
                boton.addEventListener('click', function () {
                    eliminar.querySelector('form').action = boton.dataset.url;
                    eliminar.querySelector('[data-titulo]').textContent = boton.dataset.titulo;
                    eliminar.showModal();
                });
            });
            document.querySelectorAll('dialog [data-cerrar]').forEach(function (boton) {
                boton.addEventListener('click', function () { boton.closest('dialog').close(); });
            });
        })();
    </script>
@endpush
@endsection
