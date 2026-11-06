<p>Alguien ha abierto por primera vez tu video <strong>{{ $video->titulo() }}</strong>.</p>
<p><a href="{{ $video->urlCompartir() }}">{{ $video->urlCompartir() }}</a></p>
<ul>
    <li><strong>IP:</strong> {{ $vista->ip ?? 'Desconocida' }}</li>
    <li><strong>Navegador:</strong> {{ $vista->navegador() }}</li>
    <li><strong>Fecha y hora:</strong> {{ $vista->fechaLegible() }}</li>
</ul>
<p style="color:#888">Solo se avisa la primera vez y no cuentan tus propias visitas con sesión iniciada. Las siguientes vistas quedan registradas en la página del video.</p>
