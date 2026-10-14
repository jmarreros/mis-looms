<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class PerfilTest extends TestCase
{
    use RefreshDatabase;

    private function usuario(): User
    {
        return User::factory()->create(['email' => 'a@x.com', 'password' => 'clave-vieja']);
    }

    public function test_requiere_sesion(): void
    {
        $this->get('/admin/perfil')->assertRedirect('/login');
    }

    public function test_cambia_el_nombre_sin_pedir_contrasena(): void
    {
        $u = $this->usuario();
        $this->actingAs($u)->patch('/admin/perfil', ['name' => 'Jhon', 'email' => 'a@x.com'])
            ->assertRedirect('/admin/perfil');
        $this->assertSame('Jhon', $u->fresh()->name);
    }

    public function test_cambiar_el_correo_exige_la_contrasena_actual(): void
    {
        $u = $this->usuario();
        $this->actingAs($u)->patch('/admin/perfil', ['name' => 'J', 'email' => 'nuevo@x.com'])
            ->assertSessionHasErrors('password_actual');
        $this->actingAs($u)->patch('/admin/perfil', ['name' => 'J', 'email' => 'nuevo@x.com', 'password_actual' => 'clave-vieja'])
            ->assertSessionHasNoErrors();
        $this->assertSame('nuevo@x.com', $u->fresh()->email);
    }

    public function test_cambia_la_contrasena(): void
    {
        $u = $this->usuario();
        $this->actingAs($u)->put('/admin/perfil/password', [
            'password_actual' => 'mala', 'password' => 'nueva-clave-1', 'password_confirmation' => 'nueva-clave-1',
        ])->assertSessionHasErrors('password_actual');

        $this->actingAs($u)->put('/admin/perfil/password', [
            'password_actual' => 'clave-vieja', 'password' => 'nueva-clave-1', 'password_confirmation' => 'nueva-clave-1',
        ])->assertSessionHasNoErrors();
        $this->assertTrue(Hash::check('nueva-clave-1', $u->fresh()->password));
    }
}
