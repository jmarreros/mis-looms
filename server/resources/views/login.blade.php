<!doctype html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>Acceso · {{ config('app.name') }}</title>
    <link rel="icon" type="image/svg+xml" href="{{ asset('logo.svg') }}">
    <link rel="stylesheet" href="{{ asset('css/app.css') }}">
</head>
<body>
<div class="contenedor">
    <form class="tarjeta login" method="POST" action="{{ route('login') }}">
        @csrf
        <img class="logo-login" src="{{ asset('logo.svg') }}" alt="" width="56" height="56">
        <h1>{{ config('app.name') }}</h1>
        <div class="campo">
            <label for="email">Correo</label>
            <input id="email" type="email" name="email" value="{{ old('email') }}" required autofocus autocomplete="username">
            @error('email') <div class="error">{{ $message }}</div> @enderror
        </div>
        <div class="campo">
            <label for="password">Contraseña</label>
            <input id="password" type="password" name="password" required autocomplete="current-password">
        </div>
        <div class="campo">
            <label><input type="checkbox" name="recordar" value="1"> Mantener la sesión</label>
        </div>
        <button class="primario" type="submit">Entrar</button>
    </form>
</div>
</body>
</html>
