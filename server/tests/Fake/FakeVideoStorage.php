<?php

namespace Tests\Fake;

use App\Services\VideoStorage;

/** Almacenamiento en memoria para pruebas: registra las llamadas, no toca S3. */
class FakeVideoStorage implements VideoStorage
{
    /** @var array<string, int|null> tamaños que devolverá tamano() */
    public array $tamanos = [];

    /** @var list<string> */
    public array $borrados = [];

    /** @var list<string> */
    public array $abortados = [];

    /** @var array<string, array<int, array{PartNumber:int, ETag:string}>> */
    public array $completados = [];

    public function iniciarMultipart(string $key, string $contentType): string
    {
        return 'upload-'.md5($key);
    }

    public function urlParte(string $key, string $uploadId, int $numeroParte): string
    {
        return "https://s3.test/$key?uploadId=$uploadId&partNumber=$numeroParte";
    }

    public function completarMultipart(string $key, string $uploadId, array $partes): void
    {
        $this->completados[$key] = $partes;
    }

    public function abortarMultipart(string $key, string $uploadId): void
    {
        $this->abortados[] = $key;
    }

    public function urlSubida(string $key, string $contentType): string
    {
        return "https://s3.test/$key?put";
    }

    public function tamano(string $key): ?int
    {
        return array_key_exists($key, $this->tamanos) ? $this->tamanos[$key] : 1000;
    }

    public function borrar(string $key): void
    {
        $this->borrados[] = $key;
    }

    public function urlPublica(string $key): string
    {
        return "https://cdn.test/$key";
    }
}
