@extends('layouts.admin')
@section('titulo', 'Mi perfil')
@section('estrecho', true)

@section('contenido')
    <div class="titulo-pagina">
        <h1>Mi perfil</h1>
        <p>Cambia tu nombre, tu correo de acceso y tu contraseña.</p>
    </div>

    <form class="superficie formulario" method="POST" action="{{ route('admin.perfil.actualizar') }}">
        @csrf @method('PATCH')
        <h2>Datos de la cuenta</h2>
        <label class="campo">
            Nombre
            <input class="entrada" type="text" name="name" value="{{ old('name', auth()->user()->name) }}" autocomplete="name">
        </label>
        @error('name') <div class="error">{{ $message }}</div> @enderror
        <label class="campo">
            Correo electrónico
            <input class="entrada" type="email" name="email" value="{{ old('email', auth()->user()->email) }}" required autocomplete="username">
        </label>
        @error('email') <div class="error">{{ $message }}</div> @enderror
        <label class="campo">
            Contraseña actual <span class="suave">(solo si cambias el correo)</span>
            <input class="entrada" type="password" name="password_actual" autocomplete="current-password">
        </label>
        @if (old('email') !== null) @error('password_actual') <div class="error">{{ $message }}</div> @enderror @endif
        <div><button class="boton primario" type="submit">Guardar cambios</button></div>
    </form>

    <form class="superficie formulario" method="POST" action="{{ route('admin.perfil.password') }}">
        @csrf @method('PUT')
        <h2>Cambiar contraseña</h2>
        <label class="campo">
            Contraseña actual
            <input class="entrada" type="password" name="password_actual" required autocomplete="current-password">
        </label>
        @if (old('email') === null) @error('password_actual') <div class="error">{{ $message }}</div> @enderror @endif
        <label class="campo">
            Contraseña nueva
            <input class="entrada" type="password" name="password" required minlength="8" autocomplete="new-password">
        </label>
        @error('password') <div class="error">{{ $message }}</div> @enderror
        <label class="campo">
            Repite la contraseña nueva
            <input class="entrada" type="password" name="password_confirmation" required autocomplete="new-password">
        </label>
        <div><button class="boton primario" type="submit">Cambiar contraseña</button></div>
    </form>
@endsection
