@extends('layouts.admin')
@section('titulo', 'Token de la app')
@section('estrecho', true)

@section('contenido')
    @php($activo = $tokens->first())
    <div class="titulo-pagina">
        <h1>Token de la app</h1>
        <p>Pega este token en la app de grabación para que tus videos se suban a tu cuenta. No lo compartas con nadie.</p>
    </div>

    <div class="superficie token">
        @if (session('token_nuevo'))
            <div class="copiable">
                <span class="valor">{{ session('token_nuevo') }}</span>
                <button class="boton primario" type="button" data-copiar="{{ session('token_nuevo') }}">Copiar</button>
            </div>
            <p class="suave" style="font-size: 14px">Cópialo ahora: por seguridad solo se guarda cifrado y no se volverá a mostrar.</p>
        @elseif ($activo)
            <div class="copiable">
                <span class="valor suave">{{ $activo->id }}|••••••••••••••••••••••••••••••••</span>
            </div>
        @endif

        <div class="pie">
            <span>
                @if ($activo)
                    Creado el {{ $activo->created_at->translatedFormat('j M Y') }}
                    · {{ $activo->last_used_at ? 'Último uso '.$activo->last_used_at->diffForHumans() : 'Sin usar todavía' }}
                @else
                    Todavía no hay ningún token activo.
                @endif
            </span>
            @if ($activo)
                <button class="boton chico" type="button" onclick="document.getElementById('confirmar-token').showModal()">
                    @include('partials.icono', ['nombre' => 'regenerar', 'tam' => 15]) Generar uno nuevo
                </button>
            @else
                <form method="POST" action="{{ route('admin.token.regenerar') }}">
                    @csrf
                    <button class="boton primario" type="submit">Generar token</button>
                </form>
            @endif
        </div>
    </div>

    <ol class="pasos">
        <li><span>Abre la app de grabación (Mac o Linux) y entra en su configuración.</span></li>
        <li><span>Pega la URL del servidor, <strong>{{ url('/') }}</strong>, y este token.</span></li>
        <li><span>Graba. Al terminar, el video aparecerá en <a href="{{ route('admin.videos.index') }}">Videos</a>.</span></li>
    </ol>

    @if ($activo)
        <dialog class="confirmar" id="confirmar-token">
            <h2>¿Generar un token nuevo?</h2>
            <p>El token actual dejará de funcionar y las apps no podrán subir videos hasta que pegues el nuevo.</p>
            <div class="botones">
                <button class="boton" type="button" onclick="this.closest('dialog').close()">Cancelar</button>
                <form method="POST" action="{{ route('admin.token.regenerar') }}">
                    @csrf
                    <button class="boton primario" type="submit">Generar</button>
                </form>
            </div>
        </dialog>
    @endif
@endsection
