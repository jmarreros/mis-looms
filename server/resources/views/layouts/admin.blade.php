<!doctype html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>@yield('titulo', 'Panel') · {{ config('app.name') }}</title>
    <link rel="icon" type="image/svg+xml" href="{{ asset('logo.svg') }}">
    <link rel="stylesheet" href="{{ asset('css/app.css') }}">
</head>
<body>
<header class="cabecera">
    <div class="contenedor">
        <a class="marca" href="{{ route('admin.videos.index') }}">
            <img src="{{ asset('logo.svg') }}" alt="" width="28" height="28">{{ config('app.name') }}
        </a>
        <nav>
            <a href="{{ route('admin.videos.index') }}" @class(['activo' => request()->routeIs('admin.videos.*')])>Videos</a>
            <a href="{{ route('admin.token') }}" @class(['activo' => request()->routeIs('admin.token*')])>Token de la app</a>
        </nav>
        <form method="POST" action="{{ route('logout') }}">
            @csrf
            <button class="enlace" type="submit">Salir</button>
        </form>
    </div>
</header>
<main>
    <div class="contenedor">
        @if (session('estado'))
            <div class="aviso-ok">{{ session('estado') }}</div>
        @endif
        @yield('contenido')
    </div>
</main>
</body>
</html>
