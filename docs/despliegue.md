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

## Correo
Aviso de la primera visita anónima a un video (`App\Mail\PrimeraVisita`, al correo del administrador).
- Local: Mailhog (`MAIL_MAILER=smtp`, `MAIL_HOST=127.0.0.1`, `MAIL_PORT=1025`, interfaz en :8025).
- Producción: Resend. Verificar el dominio en Resend (registros DNS en el subdominio `send.`, sin
  tocar los MX de la raíz) y poner en el `.env`: `MAIL_MAILER=resend`, `RESEND_API_KEY=re_...`,
  `MAIL_FROM_ADDRESS="avisos@tu-dominio"`, `MAIL_FROM_NAME="Mis Looms"`. El paquete `resend/resend-php`
  ya está en `composer.json`. Los fallos de envío no rompen la página; quedan en `storage/logs`.

## Producción: https://jmarreros.com/mis-looms (VPS de Hostinger, `ssh hostinger`)
Desplegado el 2026-10-14 junto a Mis Videos, con el mismo esquema (ver `/var/www/jmarreros.com/LEEME.md`
en el servidor):
- Repo clonado en `/var/www/jmarreros.com/mis-looms` con sparse checkout (solo `server/`); nginx (php-fpm 8.4)
  sirve `server/public/` desde `/etc/nginx/jmarreros.com/apps/mis-looms.conf` con
  `SCRIPT_NAME=/mis-looms/index.php`, así Laravel genera las URLs con la subcarpeta.
- `.env`: `APP_URL`/`ASSET_URL=https://jmarreros.com/mis-looms`, `SESSION_PATH=/mis-looms`,
  `SESSION_COOKIE=mis_looms_session`, `SESSION_SECURE_COOKIE=true`, SQLite con ruta absoluta, Resend.
- Cron del usuario `jmarreros`: `schedule:run` cada minuto.
- Actualizar (sin sudo): `bash /var/www/jmarreros.com/actualizar-mis-looms.sh` (git pull, composer, migrate, cachés).
- **No usar `route:cache` ni `php artisan optimize`**: en subcarpeta la raíz responde 405. Por lo mismo,
  en el código nada de rutas fijas (`Route::redirect('/', '/admin')` sacaba de la subcarpeta): usar `route()`.
- App de macOS: URL del servidor `https://jmarreros.com/mis-looms`.

## cPanel (hosting compartido, SSH + cron)
1. Subir `server/` (sin `vendor/` ni `.env`) y ejecutar `composer install --no-dev -o`.
   Requiere PHP ≥ 8.3 y salida HTTPS hacia AWS.
2. Document root = `server/public` (o symlink `public_html → server/public`).
3. Crear la base MySQL en cPanel y un `.env` de producción:
   `APP_ENV=production`, `APP_DEBUG=false`, `APP_URL=https://tu-dominio`, `DB_CONNECTION=mysql` + datos,
   claves AWS y correo con Resend (`MAIL_MAILER=resend`, `RESEND_API_KEY`, `MAIL_FROM_ADDRESS` de un
   dominio verificado en Resend; ver «Correo»). Luego `php artisan key:generate`, `php artisan migrate --force`,
   `php artisan mislooms:crear-usuario tu@correo.com`, `php artisan config:cache route:cache view:cache`.
4. Cron cada minuto: `* * * * * php /ruta/server/artisan schedule:run >> /dev/null 2>&1`
   (limpia subidas colgadas cada hora).
5. Probar: `curl -I https://tu-dominio/up` y el flujo de `docs/api.md`.
