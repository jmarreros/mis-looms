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
                <a class="tarjeta-video" href="{{ route('admin.videos.show', $video) }}">
                    @include('partials.miniatura', ['video' => $video])
                    <span class="info">
                        <span class="titulo">{{ $video->titulo() }}</span>
                        <span class="meta">
                            <span class="codigo">{{ $video->slug }}</span>
                            {{ $video->created_at->translatedFormat('j M Y') }} · {{ $video->views }} {{ $video->views === 1 ? 'vista' : 'vistas' }}
                        </span>
                    </span>
                </a>
            @endforeach
        </div>

        {{ $videos->links('pagination.mislooms') }}
    @endif
@endsection
