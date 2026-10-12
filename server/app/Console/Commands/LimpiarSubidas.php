<?php

namespace App\Console\Commands;

use App\Models\Video;
use App\Services\VideoStorage;
use Illuminate\Console\Command;

class LimpiarSubidas extends Command
{
    protected $signature = 'mislooms:limpiar-subidas';

    protected $description = 'Marca como fallidas las subidas sin completar y aborta su multipart en S3';

    public function handle(VideoStorage $almacen): int
    {
        $limite = now()->subHours(config('mislooms.upload_timeout_hours'));
        $total = 0;

        Video::where('status', Video::SUBIENDO)->where('created_at', '<', $limite)->each(
            function (Video $video) use ($almacen, &$total) {
                try {
                    if ($video->upload_id) {
                        $almacen->abortarMultipart($video->s3_key, $video->upload_id);
                    }
                } catch (\Throwable $e) {
                    $this->warn("No se pudo abortar {$video->slug}: {$e->getMessage()}");

                    return;  // se reintenta en la siguiente ejecución
                }
                $video->update(['status' => Video::FALLIDO, 'upload_id' => null]);
                $total++;
            }
        );

        $this->info("Subidas limpiadas: $total");

        return self::SUCCESS;
    }
}
