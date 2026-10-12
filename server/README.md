# Mis Looms — servidor (Laravel 13)

API para las apps nativas, página pública `/v/{slug}` y panel de administración (Blade).
El video nunca pasa por este servidor: las apps lo suben directo a S3 con URLs prefirmadas.

- Contrato de la API: [../docs/api.md](../docs/api.md)
- Desarrollo local y despliegue en cPanel: [../docs/despliegue.md](../docs/despliegue.md)

```
composer install
cp .env.example .env && php artisan key:generate
php artisan migrate
php artisan mislooms:crear-usuario tu@correo.com
php artisan serve        # http://localhost:8000
php artisan test
```
