<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('vistas', function (Blueprint $table) {
            $table->id();
            $table->foreignId('video_id')->index()->constrained('videos')->cascadeOnDelete();
            $table->string('ip', 45)->nullable(); // 45 caracteres: el largo máximo de una IPv6
            $table->text('user_agent')->nullable();
            $table->timestamp('created_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('vistas');
    }
};
