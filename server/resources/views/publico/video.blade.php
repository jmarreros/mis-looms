<!doctype html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    {{-- Enlace "no listado": no debe aparecer en buscadores. --}}
    <meta name="robots" content="noindex, nofollow">
    <title>{{ $video->titulo() }} · {{ config('app.name') }}</title>

    <meta property="og:site_name" content="{{ config('app.name') }}">
    <meta property="og:type" content="video.other">
    <meta property="og:title" content="{{ $video->titulo() }}">
    <meta property="og:url" content="{{ $video->urlCompartir() }}">
    <meta property="og:video" content="{{ $video->urlVideo() }}">
    <meta property="og:video:secure_url" content="{{ $video->urlVideo() }}">
    <meta property="og:video:type" content="video/mp4">
    @if ($video->width && $video->height)
        <meta property="og:video:width" content="{{ $video->width }}">
        <meta property="og:video:height" content="{{ $video->height }}">
    @endif
    @if ($video->urlMiniatura())
        <meta property="og:image" content="{{ $video->urlMiniatura() }}">
        <meta name="twitter:card" content="summary_large_image">
        <meta name="twitter:image" content="{{ $video->urlMiniatura() }}">
    @else
        <meta name="twitter:card" content="summary">
    @endif
    <meta name="twitter:title" content="{{ $video->titulo() }}">

    @include('partials.estilos')
</head>
<body>
<main class="publica">
    <span class="marca"><img src="{{ asset('logo.svg') }}" alt="">{{ config('app.name') }}</span>
    <video class="reproductor" controls autoplay playsinline preload="metadata"
           @if ($video->urlMiniatura()) poster="{{ $video->urlMiniatura() }}" @endif
           src="{{ $video->urlVideo() }}"></video>
    <div class="titulo-pagina">
        <h1>{{ $video->titulo() }}</h1>
        <span class="suave">
            {{ $video->created_at->translatedFormat('j M Y') }}
            · {{ $video->views }} {{ $video->views === 1 ? 'vista' : 'vistas' }}
        </span>
    </div>
</main>
</body>
</html>
