<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;

class PerfilController extends Controller
{
    public function show()
    {
        return view('admin.perfil');
    }

    /** Cambia el nombre y el correo; pide la contraseña actual solo si cambia el correo. */
    public function actualizar(Request $request): RedirectResponse
    {
        $usuario = $request->user();
        $datos = $request->validate([
            'name' => ['nullable', 'string', 'max:255'],
            'email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')->ignore($usuario->id)],
        ], [], ['name' => 'nombre', 'email' => 'correo']);

        if ($datos['email'] !== $usuario->email) {
            $request->validate(['password_actual' => ['required', 'current_password']]);
        }

        $usuario->update(['name' => $datos['name'] ?? '', 'email' => $datos['email']]);

        return redirect()->route('admin.perfil')->with('estado', 'Perfil actualizado.');
    }

    public function cambiarPassword(Request $request): RedirectResponse
    {
        $request->validate([
            'password_actual' => ['required', 'current_password'],
            'password' => ['required', 'confirmed', Password::min(8)],
        ]);

        $request->user()->update(['password' => $request->input('password')]);

        return redirect()->route('admin.perfil')->with('estado', 'Contraseña actualizada.');
    }
}
