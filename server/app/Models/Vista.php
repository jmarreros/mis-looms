<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** Una visita anónima a la página pública de un video. */
class Vista extends Model
{
    public const UPDATED_AT = null;

    /** Previsualizadores de enlaces y robots: aparecen como visitas al compartir el enlace. */
    private const ROBOTS = [
        'WhatsApp' => 'WhatsApp',
        'facebookexternalhit' => 'Facebook',
        'Slackbot' => 'Slack',
        'TelegramBot' => 'Telegram',
        'Discordbot' => 'Discord',
        'LinkedInBot' => 'LinkedIn',
        'Twitterbot' => 'X (Twitter)',
        'Googlebot' => 'Google',
        'bingbot' => 'Bing',
    ];

    /** El orden importa: Edge y Opera también dicen «Chrome», y Chrome también dice «Safari». */
    private const NAVEGADORES = [
        'Edge' => '/Edg(?:e|A|iOS)?\/(\d+)/',
        'Opera' => '/(?:OPR|OPiOS)\/(\d+)/',
        'Samsung Internet' => '/SamsungBrowser\/(\d+)/',
        'Firefox' => '/(?:Firefox|FxiOS)\/(\d+)/',
        'Chrome' => '/(?:Chrome|CriOS)\/(\d+)/',
        'Safari' => '/Version\/(\d+).*Safari\//',
    ];

    /** El orden importa: iOS dice «like Mac OS X» y Android también dice «Linux». */
    private const SISTEMAS = [
        'iPhone' => '/iPhone/',
        'iPad' => '/iPad/',
        'Android' => '/Android/',
        'Windows' => '/Windows/',
        'macOS' => '/Mac OS X|Macintosh/',
        'ChromeOS' => '/CrOS/',
        'Linux' => '/Linux/',
    ];

    protected $table = 'vistas';

    protected $guarded = [];

    /** Texto legible, como «Chrome 120 en macOS». Si no se reconoce, devuelve el user agent tal cual. */
    public function navegador(): string
    {
        $ua = (string) $this->user_agent;
        if ($ua === '') {
            return 'Desconocido';
        }

        foreach (self::ROBOTS as $marca => $nombre) {
            if (stripos($ua, $marca) !== false) {
                return "$nombre (vista previa o robot)";
            }
        }

        foreach (self::NAVEGADORES as $nombre => $patron) {
            if (preg_match($patron, $ua, $m)) {
                foreach (self::SISTEMAS as $sistema => $patronSistema) {
                    if (preg_match($patronSistema, $ua)) {
                        return "$nombre {$m[1]} en $sistema";
                    }
                }

                return "$nombre {$m[1]}";
            }
        }

        return $ua;
    }

    /** Se guarda en UTC y se muestra en la zona horaria configurada. */
    public function fechaLegible(): string
    {
        return $this->created_at->copy()->setTimezone(config('mislooms.zona_horaria'))->format('d/m/Y H:i:s');
    }
}
