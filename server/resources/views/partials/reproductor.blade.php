{{-- Reproductor con controles propios (public/js/reproductor.js): «Ver de nuevo» al terminar y
     pantalla completa sobre el marco, para que el botón también se vea ahí. Sin JS se usan los
     controles nativos del navegador. --}}
<div class="reproductor-marco" data-reproductor>
    <video class="reproductor" controls playsinline preload="metadata" @if ($autoplay ?? false) autoplay @endif
           @if ($video->urlMiniatura()) poster="{{ $video->urlMiniatura() }}" @endif
           src="{{ $video->urlVideo() }}"></video>
    <div class="capa-centro capa-inicio">
        <button class="boton-inicio" type="button" data-iniciar aria-label="Reproducir">@include('partials.icono', ['nombre' => 'play', 'tam' => 30])</button>
    </div>
    <div class="capa-centro capa-repetir">
        <button class="boton primario grande" type="button" data-repetir>@include('partials.icono', ['nombre' => 'repetir', 'tam' => 20]) Ver de nuevo</button>
    </div>
    <div class="controles" data-controles hidden>
        <input class="barra" type="range" min="0" max="1000" step="1" value="0" data-barra aria-label="Posición del video">
        <div class="fila">
            <button class="control" type="button" data-reproducir aria-label="Reproducir" title="Reproducir (espacio)">
                <span class="principal">@include('partials.icono', ['nombre' => 'play', 'tam' => 18])</span>
                <span class="alterno">@include('partials.icono', ['nombre' => 'pausa', 'tam' => 18])</span>
            </button>
            <button class="control" type="button" data-silenciar aria-label="Silenciar" title="Silenciar (m)">
                <span class="principal">@include('partials.icono', ['nombre' => 'volumen', 'tam' => 20])</span>
                <span class="alterno">@include('partials.icono', ['nombre' => 'silencio', 'tam' => 20])</span>
            </button>
            <span class="tiempo"><span data-actual>0:00</span> / <span data-total>0:00</span></span>
            <span class="espacio"></span>
            <button class="control velocidad" type="button" data-velocidad aria-label="Velocidad de reproducción" title="Velocidad">1×</button>
            <button class="control" type="button" data-pantalla-completa aria-label="Pantalla completa" title="Pantalla completa (f)">
                <span class="principal">@include('partials.icono', ['nombre' => 'ampliar', 'tam' => 20])</span>
                <span class="alterno">@include('partials.icono', ['nombre' => 'reducir', 'tam' => 20])</span>
            </button>
        </div>
    </div>
</div>
<script src="{{ asset('js/reproductor.js') }}?v={{ filemtime(public_path('js/reproductor.js')) }}" defer></script>
