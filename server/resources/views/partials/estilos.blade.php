<link rel="icon" type="image/svg+xml" href="{{ asset('logo.svg') }}">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Caprasimo&family=Figtree:wght@400;500;600;700&display=swap">
{{-- ?v= cambia al editar el archivo: así el navegador no se queda con una copia vieja. --}}
<link rel="stylesheet" href="{{ asset('css/app.css') }}?v={{ filemtime(public_path('css/app.css')) }}">
