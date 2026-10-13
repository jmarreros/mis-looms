@if ($paginator->hasPages())
    <nav class="paginacion" role="navigation" aria-label="Paginación">
        <a @class(['boton', 'chico', 'deshabilitado' => $paginator->onFirstPage()])
           href="{{ $paginator->previousPageUrl() ?? '#' }}" rel="prev">@include('partials.icono', ['nombre' => 'atras']) Anterior</a>
        <span>Página {{ $paginator->currentPage() }} de {{ $paginator->lastPage() }}</span>
        <a @class(['boton', 'chico', 'deshabilitado' => ! $paginator->hasMorePages()])
           href="{{ $paginator->nextPageUrl() ?? '#' }}" rel="next">Siguiente <span style="transform: scaleX(-1)">@include('partials.icono', ['nombre' => 'atras'])</span></a>
    </nav>
@endif
