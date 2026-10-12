<?php

namespace App\Console\Commands;

use App\Models\User;
use Illuminate\Console\Command;

use function Laravel\Prompts\password;

class CrearUsuario extends Command
{
    protected $signature = 'mislooms:crear-usuario {email} {--nombre=Admin} {--password= : Si se omite, se pide por teclado}';

    protected $description = 'Crea el usuario administrador, o cambia su contraseña si ya existe';

    public function handle(): int
    {
        $email = $this->argument('email');
        $clave = $this->option('password') ?: password('Contraseña (mínimo 8 caracteres)', required: true);

        if (strlen($clave) < 8) {
            $this->error('La contraseña debe tener al menos 8 caracteres.');

            return self::FAILURE;
        }

        $existente = User::where('email', $email)->exists();
        User::updateOrCreate(['email' => $email], ['name' => $this->option('nombre'), 'password' => $clave]);

        $this->info($existente ? "Contraseña de $email actualizada." : "Usuario $email creado.");
        if (User::count() > 1) {
            $this->warn('Hay más de un usuario: la app está pensada para uno solo.');
        }

        return self::SUCCESS;
    }
}
