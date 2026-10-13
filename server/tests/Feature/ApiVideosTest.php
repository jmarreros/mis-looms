<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Video;
use App\Services\VideoStorage;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Fake\FakeVideoStorage;
use Tests\TestCase;

class ApiVideosTest extends TestCase
{
    use RefreshDatabase;

    private FakeVideoStorage $almacen;

    protected function setUp(): void
    {
        parent::setUp();
        $this->almacen = new FakeVideoStorage;
        $this->app->instance(VideoStorage::class, $this->almacen);
    }

    private function autenticar(): void
    {
        Sanctum::actingAs(User::factory()->create());
    }

    public function test_requiere_token(): void
    {
        $this->postJson('/api/videos', ['size' => 100])->assertUnauthorized();
    }

    public function test_ping_distingue_token_valido_de_invalido(): void
    {
        $this->getJson('/api/ping')->assertUnauthorized();

        $this->autenticar();
        $this->getJson('/api/ping')->assertOk()->assertJson(['ok' => true]);
    }

    public function test_crear_devuelve_url_por_cada_parte(): void
    {
        $this->autenticar();
        $parte = config('mislooms.part_size');

        $r = $this->postJson('/api/videos', ['size' => $parte * 2 + 1, 'title' => 'Demo'])
            ->assertCreated()
            ->assertJsonPath('part_size', $parte)
            ->assertJsonPath('video.status', 'uploading')
            ->assertJsonCount(3, 'parts');

        $slug = $r->json('video.slug');
        $this->assertMatchesRegularExpression('/^[a-z0-9]{12}$/', $slug);
        $this->assertSame(route('video.ver', $slug), $r->json('video.share_url'));
        $this->assertSame([1, 2, 3], array_column($r->json('parts'), 'part_number'));
        $this->assertDatabaseHas('videos', ['slug' => $slug, 's3_key' => "videos/$slug.mp4", 'status' => 'uploading']);
    }

    public function test_un_video_pequeno_tiene_una_parte(): void
    {
        $this->autenticar();
        $this->postJson('/api/videos', ['size' => 500])->assertCreated()->assertJsonCount(1, 'parts');
    }

    public function test_rechaza_tamano_invalido_o_demasiado_grande(): void
    {
        $this->autenticar();
        $this->postJson('/api/videos', [])->assertUnprocessable();
        $this->postJson('/api/videos', ['size' => 0])->assertUnprocessable();
        $this->postJson('/api/videos', ['size' => config('mislooms.part_size') * config('mislooms.max_parts') + 1])
            ->assertUnprocessable();
    }

    public function test_flujo_completo_deja_el_video_listo(): void
    {
        $this->autenticar();
        $slug = $this->postJson('/api/videos', ['size' => 1000])->json('video.slug');
        $this->almacen->tamanos["videos/$slug.mp4"] = 1234;

        $this->postJson("/api/videos/$slug/complete", [
            'parts' => [['part_number' => 2, 'etag' => '"b"'], ['part_number' => 1, 'etag' => '"a"']],
            'duration' => 12.5, 'width' => 1920, 'height' => 1080, 'has_thumbnail' => true,
        ])->assertOk()
            ->assertJsonPath('video.status', 'ready')
            ->assertJsonPath('video.size', 1234)
            ->assertJsonPath('video.thumbnail_url', "https://cdn.test/thumbs/$slug.jpg");

        // Las partes llegan a S3 ordenadas aunque la app las envíe desordenadas.
        $this->assertSame([1, 2], array_column($this->almacen->completados["videos/$slug.mp4"], 'PartNumber'));
        $this->assertNull(Video::firstWhere('slug', $slug)->upload_id);
    }

    public function test_completar_sin_miniatura_no_guarda_clave(): void
    {
        $this->autenticar();
        $slug = $this->postJson('/api/videos', ['size' => 1000])->json('video.slug');

        $this->postJson("/api/videos/$slug/complete", ['parts' => [['part_number' => 1, 'etag' => 'x']]])
            ->assertOk()->assertJsonPath('video.thumbnail_url', null);
    }

    public function test_no_se_puede_completar_dos_veces(): void
    {
        $this->autenticar();
        $slug = $this->postJson('/api/videos', ['size' => 1000])->json('video.slug');
        $cuerpo = ['parts' => [['part_number' => 1, 'etag' => 'x']]];

        $this->postJson("/api/videos/$slug/complete", $cuerpo)->assertOk();
        $this->postJson("/api/videos/$slug/complete", $cuerpo)->assertStatus(409);
    }

    public function test_completar_exige_partes(): void
    {
        $this->autenticar();
        $slug = $this->postJson('/api/videos', ['size' => 1000])->json('video.slug');

        $this->postJson("/api/videos/$slug/complete", [])->assertUnprocessable();
    }

    public function test_volver_a_firmar_partes(): void
    {
        $this->autenticar();
        $slug = $this->postJson('/api/videos', ['size' => 1000])->json('video.slug');

        $this->postJson("/api/videos/$slug/parts", ['parts' => [3, 5]])
            ->assertOk()->assertJsonCount(2, 'parts')->assertJsonPath('parts.1.part_number', 5);
    }

    public function test_miniatura_devuelve_url_firmada_con_content_type(): void
    {
        $this->autenticar();
        $slug = $this->postJson('/api/videos', ['size' => 1000])->json('video.slug');

        $this->postJson("/api/videos/$slug/thumbnail")
            ->assertOk()
            ->assertJsonPath('upload_url', "https://s3.test/thumbs/$slug.jpg?put")
            ->assertJsonPath('headers.Content-Type', 'image/jpeg');
    }

    public function test_abortar_marca_fallido_y_aborta_en_s3(): void
    {
        $this->autenticar();
        $slug = $this->postJson('/api/videos', ['size' => 1000])->json('video.slug');

        $this->postJson("/api/videos/$slug/abort")->assertOk()->assertJsonPath('video.status', 'failed');
        $this->assertSame(["videos/$slug.mp4"], $this->almacen->abortados);
        $this->postJson("/api/videos/$slug/abort")->assertStatus(409);
    }
}
