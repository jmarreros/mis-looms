<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Video;
use App\Services\VideoStorage;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Fake\FakeVideoStorage;
use Tests\TestCase;

class PanelTest extends TestCase
{
    use RefreshDatabase;

    private FakeVideoStorage $almacen;

    protected function setUp(): void
    {
        parent::setUp();
        $this->almacen = new FakeVideoStorage;
        $this->app->instance(VideoStorage::class, $this->almacen);
    }

    private function video(array $datos = []): Video
    {
        $slug = Video::nuevoSlug();

        return Video::create($datos + [
            'slug' => $slug, 's3_key' => "videos/$slug.mp4", 'status' => Video::LISTO,
            'size' => 2048, 'duration' => 65,
        ]);
    }

    // --- Página pública ---

    public function test_pagina_publica_muestra_el_video_y_cuenta_la_vista(): void
    {
        $v = $this->video(['title' => 'Mi demo', 'thumbnail_key' => 'thumbs/x.jpg']);

        $this->get("/v/{$v->slug}")
            ->assertOk()
            ->assertSee('Mi demo')
            ->assertSee("https://cdn.test/{$v->s3_key}", false)
            ->assertSee('og:image', false)
            ->assertSee('noindex', false);

        $this->assertSame(1, $v->fresh()->views);
    }

    public function test_las_vistas_del_administrador_no_cuentan(): void
    {
        $v = $this->video();
        $this->actingAs(User::factory()->create())->get("/v/{$v->slug}")->assertOk();

        $this->assertSame(0, $v->fresh()->views);
    }

    public function test_pagina_publica_404_si_no_esta_listo_o_no_existe(): void
    {
        $subiendo = $this->video(['status' => Video::SUBIENDO]);
        $fallido = $this->video(['status' => Video::FALLIDO]);

        $this->get("/v/{$subiendo->slug}")->assertNotFound();
        $this->get("/v/{$fallido->slug}")->assertNotFound();
        $this->get('/v/inexistente')->assertNotFound();
    }

    // --- Acceso ---

    public function test_el_panel_exige_sesion(): void
    {
        $v = $this->video();

        $this->get('/admin')->assertRedirect('/login');
        $this->patch("/admin/videos/{$v->slug}", ['title' => 'x'])->assertRedirect('/login');
        $this->delete("/admin/videos/{$v->slug}")->assertRedirect('/login');
        $this->get('/admin/token')->assertRedirect('/login');
        $this->assertDatabaseHas('videos', ['id' => $v->id]);
    }

    public function test_login_correcto_e_incorrecto(): void
    {
        User::factory()->create(['email' => 'yo@ejemplo.com', 'password' => 'secreta-123']);

        $this->post('/login', ['email' => 'yo@ejemplo.com', 'password' => 'mala'])
            ->assertSessionHasErrors('email');
        $this->assertGuest();

        $this->post('/login', ['email' => 'yo@ejemplo.com', 'password' => 'secreta-123'])
            ->assertRedirect('/admin');
        $this->assertAuthenticated();
    }

    public function test_cerrar_sesion(): void
    {
        $this->actingAs(User::factory()->create())->post('/logout')->assertRedirect('/login');
        $this->assertGuest();
    }

    public function test_la_pagina_publica_sin_sesion_no_ofrece_acciones_de_administrador(): void
    {
        $v = $this->video(['title' => 'Mi demo']);

        $this->get("/v/{$v->slug}")
            ->assertOk()
            ->assertSee('Mi demo')
            ->assertDontSee('data-copiar', false)
            ->assertDontSee('confirmar-eliminar', false)
            ->assertDontSee('name="title"', false);
    }

    public function test_el_administrador_ve_en_la_pagina_publica_el_detalle_con_acciones(): void
    {
        $v = $this->video(['title' => 'Mi demo']);

        $this->actingAs(User::factory()->create())
            ->get("/v/{$v->slug}")
            ->assertOk()
            ->assertSee('Mi demo')
            ->assertSee('data-copiar="'.$v->urlCompartir().'"', false)
            ->assertSee('action="'.route('admin.videos.update', $v).'"', false)
            ->assertSee('confirmar-eliminar', false)
            ->assertSee('Token de la app');

        $this->assertSame(0, $v->fresh()->views);  // sus visitas no cuentan
    }

    public function test_logo_de_la_pagina_publica_lleva_al_inicio(): void
    {
        $v = $this->video();

        $this->get("/v/{$v->slug}")->assertSee('href="'.url('/').'"', false);

        // Sin sesión, el inicio termina en el login; con sesión de administrador, en el listado.
        $this->followingRedirects()->get('/')->assertOk()->assertSee('Entrar');
        $this->actingAs(User::factory()->create())->followingRedirects()->get('/')->assertOk()->assertSee('Token de la app');
    }

    // --- Administración ---

    public function test_listado_con_busqueda(): void
    {
        $this->video(['title' => 'Reunión de equipo']);
        $this->video(['title' => 'Tutorial de Laravel']);

        $this->actingAs(User::factory()->create())
            ->get('/admin?q=Tutorial')
            ->assertOk()
            ->assertSee('Tutorial de Laravel')
            ->assertDontSee('Reunión de equipo');
    }

    public function test_listado_vacio_y_sin_resultados(): void
    {
        $usuario = User::factory()->create();
        $this->actingAs($usuario)->get('/admin')->assertOk()->assertSee('Todavía no has subido ningún video.');

        $this->video(['title' => 'Reunión de equipo']);
        $this->actingAs($usuario)->get('/admin?q=zzz')->assertOk()->assertSee('Sin resultados para');
    }

    public function test_detalle_del_video(): void
    {
        $v = $this->video(['title' => 'Mi demo', 'width' => 1920, 'height' => 1080]);

        $this->actingAs(User::factory()->create())
            ->get("/admin/videos/{$v->slug}")
            ->assertOk()
            ->assertSee('Mi demo')
            ->assertSee($v->urlCompartir())
            ->assertSee('1920 × 1080');
    }

    public function test_renombrar(): void
    {
        $v = $this->video(['title' => 'Antes']);

        $this->actingAs(User::factory()->create())
            ->patch("/admin/videos/{$v->slug}", ['title' => 'Después'])
            ->assertRedirect();

        $this->assertSame('Después', $v->fresh()->title);
    }

    public function test_eliminar_borra_de_s3_y_de_la_base_de_datos(): void
    {
        $v = $this->video(['thumbnail_key' => 'thumbs/abc.jpg']);

        $this->actingAs(User::factory()->create())->delete("/admin/videos/{$v->slug}")->assertRedirect();

        $this->assertDatabaseMissing('videos', ['id' => $v->id]);
        $this->assertSame([$v->s3_key, 'thumbs/abc.jpg'], $this->almacen->borrados);
    }

    public function test_cada_video_del_listado_tiene_copiar_renombrar_y_eliminar(): void
    {
        $listo = $this->video(['title' => 'Terminado']);
        $subiendo = $this->video(['title' => 'En curso', 'status' => Video::SUBIENDO, 'upload_id' => 'u1']);

        $r = $this->actingAs(User::factory()->create())->get('/admin')->assertOk();

        $r->assertSee('data-copiar="'.$listo->urlCompartir().'"', false)
            ->assertDontSee('data-copiar="'.$subiendo->urlCompartir().'"', false)
            ->assertSee('data-url="'.route('admin.videos.update', $listo).'"', false)
            ->assertSee('data-url="'.route('admin.videos.destroy', $subiendo).'"', false);
        $this->assertSame(2, substr_count($r->getContent(), 'data-renombrar data-url='));
        $this->assertSame(2, substr_count($r->getContent(), 'data-eliminar data-url='));
    }

    public function test_eliminar_desde_el_listado_vuelve_a_la_misma_pagina_y_busqueda(): void
    {
        $v = $this->video(['title' => 'Demo']);

        $this->actingAs(User::factory()->create())
            ->from('/admin?q=Demo&page=2')
            ->delete("/admin/videos/{$v->slug}")
            ->assertRedirect('/admin?q=Demo&page=2')
            ->assertSessionHas('estado', 'Video eliminado.');
    }

    public function test_eliminar_desde_el_detalle_vuelve_al_listado(): void
    {
        $v = $this->video();

        $this->actingAs(User::factory()->create())
            ->from("/admin/videos/{$v->slug}")
            ->delete("/admin/videos/{$v->slug}", ['desde_detalle' => 1])
            ->assertRedirect('/admin');
    }

    public function test_una_pagina_que_se_queda_vacia_redirige_a_la_ultima(): void
    {
        foreach (range(1, 13) as $i) {
            $this->video(['title' => "Video $i"]);
        }
        $usuario = User::factory()->create();

        $this->actingAs($usuario)->get('/admin?page=2')->assertOk();                       // el 13.º está en la 2
        Video::latest('id')->skip(12)->first()->delete();                                  // desaparece el único de la 2
        $this->actingAs($usuario)->get('/admin?page=2')->assertRedirect('/admin');         // vuelve a la única que queda
    }

    public function test_eliminar_una_subida_en_curso_la_aborta(): void
    {
        $v = $this->video(['status' => Video::SUBIENDO, 'upload_id' => 'u1']);

        $this->actingAs(User::factory()->create())->delete("/admin/videos/{$v->slug}");

        $this->assertSame([$v->s3_key], $this->almacen->abortados);
        $this->assertDatabaseMissing('videos', ['id' => $v->id]);
    }

    public function test_regenerar_token_revoca_el_anterior_y_funciona_en_la_api(): void
    {
        $usuario = User::factory()->create();
        $viejo = $usuario->createToken('apps')->plainTextToken;

        $r = $this->actingAs($usuario)->post('/admin/token')->assertRedirect('/admin/token');
        $nuevo = session('token_nuevo');

        $this->assertNotNull($nuevo);
        $this->assertSame(1, $usuario->tokens()->count());
        $this->assertNotSame($viejo, $nuevo);

        $this->app['auth']->forgetGuards();
        $this->withToken($nuevo)->postJson('/api/videos', ['size' => 10])->assertCreated();
    }

    // --- Cron ---

    public function test_limpieza_marca_fallidas_las_subidas_antiguas(): void
    {
        $vieja = $this->video(['status' => Video::SUBIENDO, 'upload_id' => 'u1']);
        $vieja->forceFill(['created_at' => now()->subHours(25)])->save();
        $reciente = $this->video(['status' => Video::SUBIENDO, 'upload_id' => 'u2']);
        $lista = $this->video();
        $lista->forceFill(['created_at' => now()->subDays(30)])->save();

        $this->artisan('mislooms:limpiar-subidas')->assertSuccessful();

        $this->assertSame('failed', $vieja->fresh()->status);
        $this->assertSame('uploading', $reciente->fresh()->status);
        $this->assertSame('ready', $lista->fresh()->status);
        $this->assertSame([$vieja->s3_key], $this->almacen->abortados);
    }
}
