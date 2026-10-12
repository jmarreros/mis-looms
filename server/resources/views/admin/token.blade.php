@extends('layouts.admin')
@section('titulo', 'Token de la app')

@section('contenido')
    <h1>Token de la app</h1>

    <div class="tarjeta">
        <p>Las apps de Mac y Linux usan este token para subir videos. Pégalo en su configuración junto con
            la URL del servidor: <strong>{{ url('/') }}</strong></p>

        @if (session('token_nuevo'))
            <div class="aviso-ok">
                Copia el token ahora: no se volverá a mostrar.
            </div>
            <code class="token">{{ session('token_nuevo') }}</code>
        @else
            <p class="meta">
                @if ($tokens->isEmpty())
                    Todavía no hay ningún token activo.
                @else
                    Token activo creado el {{ $tokens->first()->created_at->format('d/m/Y H:i') }}.
                    @if ($tokens->first()->last_used_at)
                        Último uso: {{ $tokens->first()->last_used_at->format('d/m/Y H:i') }}.
                    @endif
                @endif
            </p>
        @endif

        <form method="POST" action="{{ route('admin.token.regenerar') }}" style="margin-top:16px"
              onsubmit="return confirm('Se revocará el token actual y las apps dejarán de funcionar hasta que pegues el nuevo. ¿Continuar?')">
            @csrf
            <button class="primario" type="submit">{{ $tokens->isEmpty() ? 'Generar token' : 'Regenerar token' }}</button>
        </form>
    </div>
@endsection
