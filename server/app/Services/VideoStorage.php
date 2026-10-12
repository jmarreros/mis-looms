<?php

namespace App\Services;

/**
 * Operaciones sobre el almacenamiento de videos (S3). Existe como interfaz para poder
 * sustituirla en las pruebas: el video nunca pasa por el servidor, solo se firman URLs.
 */
interface VideoStorage
{
    /** Inicia una subida multipart y devuelve su upload_id. */
    public function iniciarMultipart(string $key, string $contentType): string;

    /** URL prefirmada (PUT) para subir una parte. */
    public function urlParte(string $key, string $uploadId, int $numeroParte): string;

    /** @param array<int, array{PartNumber:int, ETag:string}> $partes */
    public function completarMultipart(string $key, string $uploadId, array $partes): void;

    public function abortarMultipart(string $key, string $uploadId): void;

    /** URL prefirmada (PUT) para subir un objeto pequeño, p. ej. la miniatura. */
    public function urlSubida(string $key, string $contentType): string;

    /** Tamaño en bytes del objeto, o null si no existe. */
    public function tamano(string $key): ?int;

    public function borrar(string $key): void;

    public function urlPublica(string $key): string;
}
