{{-- Iconos Lucide con trazo 2.75 (como pide el diseño). Uso: @include('partials.icono', ['nombre' => 'play', 'tam' => 20]) --}}
@php($tam = $tam ?? 16)
@if ($nombre === 'play')
    <svg width="{{ $tam }}" height="{{ $tam }}" viewBox="0 0 24 24" fill="{{ $color ?? 'currentColor' }}" stroke="{{ $color ?? 'currentColor' }}" stroke-width="2.75" stroke-linejoin="round" aria-hidden="true"><path d="M7 4v16l13-8z"/></svg>
@else
    <svg width="{{ $tam }}" height="{{ $tam }}" viewBox="0 0 24 24" fill="none" stroke="{{ $color ?? 'currentColor' }}" stroke-width="2.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        @switch($nombre)
            @case('buscar') <circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/> @break
            @case('salir') <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/> @break
            @case('atras') <path d="m15 18-6-6 6-6"/> @break
            @case('descargar') <path d="M12 15V3"/><path d="m7 10 5 5 5-5"/><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/> @break
            @case('eliminar') <path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6l-1 14H6L5 6"/> @break
            @case('regenerar') <path d="M21 12a9 9 0 1 1-3-6.7L21 8"/><path d="M21 3v5h-5"/> @break
            @case('abrir') <path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/> @break
            @case('ok') <path d="M20 6 9 17l-5-5"/> @break
        @endswitch
    </svg>
@endif
