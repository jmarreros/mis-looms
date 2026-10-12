<?php

namespace App\Services;

use Aws\Exception\AwsException;
use Aws\S3\S3Client;

class S3VideoStorage implements VideoStorage
{
    private ?S3Client $cliente = null;

    /** @param array<string, mixed> $config config('mislooms') */
    public function __construct(private array $config) {}

    private function s3(): S3Client
    {
        return $this->cliente ??= new S3Client([
            'version' => 'latest',
            'region' => $this->config['region'],
            'credentials' => [
                'key' => $this->config['key'],
                'secret' => $this->config['secret'],
            ],
        ]);
    }

    private function bucket(): string
    {
        return $this->config['bucket'];
    }

    private function vigencia(): string
    {
        return '+'.$this->config['presign_minutes'].' minutes';
    }

    public function iniciarMultipart(string $key, string $contentType): string
    {
        $r = $this->s3()->createMultipartUpload([
            'Bucket' => $this->bucket(),
            'Key' => $key,
            'ContentType' => $contentType,
            'CacheControl' => 'public, max-age=31536000',
        ]);

        return $r['UploadId'];
    }

    public function urlParte(string $key, string $uploadId, int $numeroParte): string
    {
        $cmd = $this->s3()->getCommand('UploadPart', [
            'Bucket' => $this->bucket(),
            'Key' => $key,
            'UploadId' => $uploadId,
            'PartNumber' => $numeroParte,
        ]);

        return (string) $this->s3()->createPresignedRequest($cmd, $this->vigencia())->getUri();
    }

    public function completarMultipart(string $key, string $uploadId, array $partes): void
    {
        $this->s3()->completeMultipartUpload([
            'Bucket' => $this->bucket(),
            'Key' => $key,
            'UploadId' => $uploadId,
            'MultipartUpload' => ['Parts' => $partes],
        ]);
    }

    public function abortarMultipart(string $key, string $uploadId): void
    {
        try {
            $this->s3()->abortMultipartUpload([
                'Bucket' => $this->bucket(),
                'Key' => $key,
                'UploadId' => $uploadId,
            ]);
        } catch (AwsException $e) {
            // Si la subida ya no existe (completada o abortada antes) no hay nada que abortar.
            if ($e->getAwsErrorCode() !== 'NoSuchUpload') {
                throw $e;
            }
        }
    }

    public function urlSubida(string $key, string $contentType): string
    {
        $cmd = $this->s3()->getCommand('PutObject', [
            'Bucket' => $this->bucket(),
            'Key' => $key,
            'ContentType' => $contentType,
        ]);

        return (string) $this->s3()->createPresignedRequest($cmd, $this->vigencia())->getUri();
    }

    public function tamano(string $key): ?int
    {
        try {
            $r = $this->s3()->headObject(['Bucket' => $this->bucket(), 'Key' => $key]);

            return (int) $r['ContentLength'];
        } catch (AwsException $e) {
            if ($e->getStatusCode() === 404) {
                return null;
            }
            throw $e;
        }
    }

    public function borrar(string $key): void
    {
        $this->s3()->deleteObject(['Bucket' => $this->bucket(), 'Key' => $key]);
    }

    public function urlPublica(string $key): string
    {
        $base = $this->config['public_url']
            ?: sprintf('https://%s.s3.%s.amazonaws.com', $this->bucket(), $this->config['region']);

        return rtrim($base, '/').'/'.$key;
    }
}
