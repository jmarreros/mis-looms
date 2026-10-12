<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('videos', function (Blueprint $table) {
            $table->id();
            $table->string('slug', 32)->unique();
            $table->string('title')->nullable();
            $table->string('s3_key');
            $table->string('thumbnail_key')->nullable();
            $table->string('upload_id', 512)->nullable();
            $table->unsignedBigInteger('size')->nullable();
            $table->float('duration')->nullable();
            $table->unsignedInteger('width')->nullable();
            $table->unsignedInteger('height')->nullable();
            $table->string('status', 16)->default('uploading')->index(); // uploading|ready|failed
            $table->unsignedBigInteger('views')->default(0);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('videos');
    }
};
