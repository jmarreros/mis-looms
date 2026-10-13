<!doctype html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>Acceso · {{ config('app.name') }}</title>
    @include('partials.estilos')
</head>
<body>
<div class="login">
    <div class="login-panel">
        <span class="marca"><img src="{{ asset('logo.svg') }}" alt="">{{ config('app.name') }}</span>
        <div class="login-intro">
            <h1>Tus grabaciones, en un solo lugar.</h1>
            <p>Entra para ver, compartir y organizar los videos que grabas desde la app.</p>
        </div>
        <form method="POST" action="{{ route('login') }}">
            @csrf
            <label class="campo">
                Correo electrónico
                <input class="entrada" type="email" name="email" value="{{ old('email') }}" placeholder="tu@correo.com"
                       required autofocus autocomplete="username">
            </label>
            @error('email') <div class="error">{{ $message }}</div> @enderror
            <label class="campo">
                Contraseña
                <input class="entrada" type="password" name="password" placeholder="••••••••" required autocomplete="current-password">
            </label>
            <label class="casilla"><input type="checkbox" name="recordar" value="1"> Mantener la sesión</label>
            <button class="boton primario grande" type="submit">Entrar</button>
        </form>
    </div>
    <div class="ilustracion" aria-hidden="true">
        <div class="circulo c1"></div>
        <div class="circulo c2"></div>
        <div class="pantalla">
            <div class="boton-play">@include('partials.icono', ['nombre' => 'play', 'tam' => 28, 'color' => '#1c1a17'])</div>
            <div class="etiqueta-grabando"><span class="punto"></span>Grabando · 02:14</div>
        </div>
    </div>
</div>
</body>
</html>
