# Desarrollo local y despliegue

## Desarrollo local (`server/`)
```
cd server
composer install
cp .env.example .env && php artisan key:generate   # .env ya viene con el bucket
php artisan migrate
php artisan mislooms:crear-usuario tu@correo.com    # pide la contraseña
php artisan serve
php artisan test                                    # no toca S3 (almacenamiento falso)
```
Para subir de verdad a S3 hay que rellenar en `server/.env` (nunca en git: el repositorio es público):
```
AWS_ACCESS_KEY_ID=…        # usuario IAM mis-looms-laravel
AWS_SECRET_ACCESS_KEY=…
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=mis-looms-jmarreros
```
Entra en `/login`, ve a "Token de la app" y genera el token para las apps.

## S3
Bucket `mis-looms-jmarreros` (us-east-1): política pública de lectura solo en `videos/*` y
`thumbs/*`, sin `ListBucket`; Block Public Access con las dos casillas de ACL activas; regla de
ciclo de vida que aborta multipart incompletos a 1 día; usuario IAM `mis-looms-laravel` con
`PutObject, GetObject, DeleteObject, AbortMultipartUpload, ListMultipartUploadParts` sobre
`bucket/*` y `ListBucketMultipartUploads` sobre el bucket.

## cPanel (hosting compartido, SSH + cron)
1. Subir `server/` (sin `vendor/` ni `.env`) y ejecutar `composer install --no-dev -o`.
   Requiere PHP ≥ 8.3 y salida HTTPS hacia AWS.
2. Document root = `server/public` (o symlink `public_html → server/public`).
3. Crear la base MySQL en cPanel y un `.env` de producción:
   `APP_ENV=production`, `APP_DEBUG=false`, `APP_URL=https://tu-dominio`, `DB_CONNECTION=mysql` + datos,
   claves AWS. Luego `php artisan key:generate`, `php artisan migrate --force`,
   `php artisan mislooms:crear-usuario tu@correo.com`, `php artisan config:cache route:cache view:cache`.
4. Cron cada minuto: `* * * * * php /ruta/server/artisan schedule:run >> /dev/null 2>&1`
   (limpia subidas colgadas cada hora).
5. Probar: `curl -I https://tu-dominio/up` y el flujo de `docs/api.md`.
