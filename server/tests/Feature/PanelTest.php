<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Video;
use App\Models\Vista;
use App\Services\VideoStorage;
use App\Mail\PrimeraVisita;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Mail;
use PHPUnit\Framework\Attributes\DataProvider;
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

    public function test_la_pagina_publica_muestra_el_contador_ya_actualizado(): void
    {
        $v = $this->video();

        $this->get("/v/{$v->slug}")->assertOk()->assertSee('1 vista')->assertDontSee('0 vistas');
        $this->get("/v/{$v->slug}")->assertOk()->assertSee('2 vistas');
    }

    public function test_el_reproductor_ofrece_ver_de_nuevo_con_y_sin_sesion(): void
    {
        $v = $this->video();

        $this->get("/v/{$v->slug}")
            ->assertOk()
            ->assertSee('data-repetir', false)
            ->assertSee('Ver de nuevo')
            ->assertSee('js/reproductor.js', false);

        $this->actingAs(User::factory()->create())->get("/v/{$v->slug}")
            ->assertOk()
            ->assertSee('data-repetir', false)
            ->assertSee('data-pantalla-completa', false);
    }

    public function test_avisa_por_correo_solo_en_la_primera_visita_anonima(): void
    {
        Mail::fake();
        User::factory()->create(['email' => 'admin@x.com']);
        $v = $this->video();

        $this->get("/v/{$v->slug}")->assertOk();
        $this->get("/v/{$v->slug}")->assertOk();

        Mail::assertSentCount(1);
        Mail::assertSent(PrimeraVisita::class, fn ($m) => $m->hasTo('admin@x.com'));
        $this->assertSame(2, $v->fresh()->views);
    }

    public function test_la_visita_del_administrador_no_envia_correo(): void
    {
        Mail::fake();
        $admin = User::factory()->create();
        $v = $this->video();

        $this->actingAs($admin)->get("/v/{$v->slug}")->assertOk();

        Mail::assertNothingSent();
    }

    public function test_las_vistas_del_administrador_no_cuentan(): void
    {
        $v = $this->video();
        $this->actingAs(User::factory()->create())->get("/v/{$v->slug}")->assertOk();

        $this->assertSame(0, $v->fresh()->views);
    }

    // --- Historial de vistas ---

    private const AGENTE_CHROME = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

    private function visitar(Video $v, string $ip = '203.0.113.7', string $agente = self::AGENTE_CHROME)
    {
        return $this->withServerVariables(['REMOTE_ADDR' => $ip])
            ->withHeader('User-Agent', $agente)
            ->get("/v/{$v->slug}");
    }

    public function test_cada_visita_anonima_guarda_ip_navegador_y_fecha(): void
    {
        $v = $this->video();

        $this->visitar($v)->assertOk();
        $this->visitar($v, '198.51.100.9')->assertOk();

        $this->assertSame(2, $v->vistas()->count());
        $this->assertEqualsCanonicalizing(['203.0.113.7', '198.51.100.9'], $v->vistas()->pluck('ip')->all());
        $this->assertSame(self::AGENTE_CHROME, $v->vistas()->first()->user_agent);
        $this->assertNotNull($v->vistas()->first()->created_at);
    }

    public function test_no_se_puede_falsear_la_ip_con_una_cabecera(): void
    {
        $v = $this->video();

        $this->withHeader('X-Forwarded-For', '1.2.3.4')->visitar($v)->assertOk();

        $this->assertSame('203.0.113.7', $v->vistas()->first()->ip);
    }

    public function test_el_correo_incluye_ip_navegador_y_fecha(): void
    {
        Mail::fake();
        User::factory()->create(['email' => 'admin@x.com']);
        config(['mislooms.zona_horaria' => 'America/Lima']);
        $v = $this->video();

        $this->travelTo('2026-11-06 20:30:15 UTC');
        $this->visitar($v)->assertOk();

        Mail::assertSent(PrimeraVisita::class, function (PrimeraVisita $correo) {
            $html = $correo->render();

            return str_contains($html, '203.0.113.7')
                && str_contains($html, 'Chrome 120 en macOS')
                && str_contains($html, '06/11/2026 15:30:15');
        });
    }

    public function test_el_administrador_ve_el_historial_y_el_publico_no(): void
    {
        $v = $this->video();
        $this->visitar($v)->assertOk();

        $this->flushHeaders();
        $this->get("/v/{$v->slug}")->assertOk()->assertDontSee('203.0.113.7')->assertDontSee('Historial de vistas');

        $admin = User::factory()->create();
        $this->actingAs($admin)->get("/v/{$v->slug}")
            ->assertOk()->assertSee('Historial de vistas')->assertSee('203.0.113.7')->assertSee('Chrome 120 en macOS');
        $this->actingAs($admin)->get(route('admin.videos.show', $v))
            ->assertOk()->assertSee('203.0.113.7');
    }

    public function test_la_visita_del_administrador_no_se_registra(): void
    {
        $v = $this->video();

        $this->actingAs(User::factory()->create())->get("/v/{$v->slug}")->assertOk();

        $this->assertSame(0, $v->vistas()->count());
    }

    public function test_el_historial_avisa_de_las_vistas_sin_datos_y_pagina(): void
    {
        $v = $this->video(['views' => 3]);
        $admin = User::factory()->create();

        $this->actingAs($admin)->get(route('admin.videos.show', $v))
            ->assertSee('Aún no hay vistas registradas')->assertSee('3 vistas son anteriores');

        foreach (range(1, 21) as $i) {
            $v->vistas()->create(['ip' => "203.0.113.$i"]);
        }
        $v->update(['views' => 21]);

        $this->actingAs($admin)->get(route('admin.videos.show', $v))
            ->assertSee('203.0.113.21')->assertDontSee('203.0.113.1<', false)->assertSee('vistas=2#vistas', false);
        $this->actingAs($admin)->get(route('admin.videos.show', $v).'?vistas=2')
            ->assertSee('203.0.113.1<', false);
    }

    public function test_al_eliminar_el_video_se_borra_su_historial(): void
    {
        $v = $this->video();
        $this->visitar($v)->assertOk();

        $v->eliminarCompleto($this->almacen);

        $this->assertDatabaseCount('vistas', 0);
    }

    #[DataProvider('agentes')]
    public function test_reconoce_el_navegador(?string $agente, string $esperado): void
    {
        $this->assertSame($esperado, (new Vista(['user_agent' => $agente]))->navegador());
    }

    public static function agentes(): array
    {
        return [
            'Chrome en Mac' => [self::AGENTE_CHROME, 'Chrome 120 en macOS'],
            'Edge' => ['Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0', 'Edge 120 en Windows'],
            'Firefox' => ['Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0', 'Firefox 121 en Linux'],
            'Safari en iPhone' => ['Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1', 'Safari 17 en iPhone'],
            'Chrome en Android' => ['Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36', 'Chrome 120 en Android'],
            'WhatsApp' => ['WhatsApp/2.23.20.0 A', 'WhatsApp (vista previa o robot)'],
            'Sin reconocer' => ['curl/8.4.0', 'curl/8.4.0'],
            'Vacío' => [null, 'Desconocido'],
        ];
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
