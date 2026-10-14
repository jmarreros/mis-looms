<!doctype html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>@yield('titulo', 'Panel') · {{ config('app.name') }}</title>
    @include('partials.estilos')
</head>
<body>
<header class="cabecera">
    <a class="marca" href="{{ route('admin.videos.index') }}">
        <img src="{{ asset('logo.svg') }}" alt="">{{ config('app.name') }}
    </a>
    <nav class="pestanas">
        <a href="{{ route('admin.videos.index') }}" @class(['activo' => request()->routeIs('admin.videos.*')])>Videos</a>
        <a href="{{ route('admin.token') }}" @class(['activo' => request()->routeIs('admin.token*')])>Token de la app</a>
    </nav>
    <div class="cuenta">
        <a class="avatar" href="{{ route('admin.perfil') }}" title="Mi perfil · {{ auth()->user()->email }}">{{ mb_strtoupper(mb_substr(auth()->user()->name ?: auth()->user()->email, 0, 1)) }}</a>
        <form method="POST" action="{{ route('logout') }}">
            @csrf
            <button class="boton chico" type="submit">@include('partials.icono', ['nombre' => 'salir']) Salir</button>
        </form>
    </div>
</header>
<main @class(['principal', 'estrecho' => View::hasSection('estrecho')])>
    @if (session('estado'))
        <div class="aviso-ok">@include('partials.icono', ['nombre' => 'ok']) {{ session('estado') }}</div>
    @endif
    @yield('contenido')
</main>
<script>
    // Botones "Copiar": copian data-copiar al portapapeles y confirman durante un momento.
    document.querySelectorAll('[data-copiar]').forEach(function (boton) {
        boton.addEventListener('click', function () {
            navigator.clipboard.writeText(boton.dataset.copiar).then(function () {
                var original = boton.innerHTML;
                boton.textContent = 'Copiado';
                setTimeout(function () { boton.innerHTML = original; }, 1600);
            });
        });
    });
</script>
@stack('scripts')
</body>
</html>
