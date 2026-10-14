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
            @case('pausa') <rect x="6" y="4" width="4" height="16" rx="1" fill="{{ $color ?? 'currentColor' }}"/><rect x="14" y="4" width="4" height="16" rx="1" fill="{{ $color ?? 'currentColor' }}"/> @break
            @case('volumen') <path d="M11 5 6 9H2v6h4l5 4z"/><path d="M15.5 8.5a5 5 0 0 1 0 7"/><path d="M19 5a10 10 0 0 1 0 14"/> @break
            @case('silencio') <path d="M11 5 6 9H2v6h4l5 4z"/><path d="m22 9-6 6"/><path d="m16 9 6 6"/> @break
            @case('ampliar') <path d="M8 3H5a2 2 0 0 0-2 2v3"/><path d="M21 8V5a2 2 0 0 0-2-2h-3"/><path d="M3 16v3a2 2 0 0 0 2 2h3"/><path d="M16 21h3a2 2 0 0 0 2-2v-3"/> @break
            @case('reducir') <path d="M8 3v3a2 2 0 0 1-2 2H3"/><path d="M21 8h-3a2 2 0 0 1-2-2V3"/><path d="M3 16h3a2 2 0 0 1 2 2v3"/><path d="M16 21v-3a2 2 0 0 1 2-2h3"/> @break
            @case('repetir') <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/> @break
            @case('regenerar') <path d="M21 12a9 9 0 1 1-3-6.7L21 8"/><path d="M21 3v5h-5"/> @break
            @case('abrir') <path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/> @break
            @case('copiar') <rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/> @break
            @case('editar') <path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"/><path d="m15 5 4 4"/> @break
            @case('ok') <path d="M20 6 9 17l-5-5"/> @break
        @endswitch
    </svg>
@endif
