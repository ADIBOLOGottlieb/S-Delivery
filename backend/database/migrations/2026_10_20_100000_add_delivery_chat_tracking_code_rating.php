<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * S-Delivery 2.0 : discussion par course (client, livreur, agence), position du livreur en direct,
 * code de remise demandé au destinataire et note donnée au livreur.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('delivery_messages', function (Blueprint $table) {
            $table->id();
            $table->foreignId('delivery_id')->constrained()->cascadeOnDelete();
            $table->foreignId('sender_id')->nullable()->constrained('users')->nullOnDelete(); // null = message système
            $table->text('body')->nullable();
            $table->foreignId('media_id')->nullable()->constrained('media')->nullOnDelete();
            $table->decimal('lat', 10, 7)->nullable();
            $table->decimal('lng', 10, 7)->nullable();
            $table->timestamps();

            $table->index(['delivery_id', 'id']);
        });

        Schema::table('deliveries', function (Blueprint $table) {
            // Code à 4 chiffres que le destinataire donne au livreur (null : anciennes livraisons).
            $table->string('dropoff_code', 6)->nullable()->after('cancel_reason');
            // Messages lus par identifiant, pour chaque participant de la discussion.
            $table->unsignedBigInteger('last_message_id')->nullable()->after('dropoff_code');
            $table->unsignedBigInteger('client_read_id')->nullable()->after('last_message_id');
            $table->unsignedBigInteger('courier_read_id')->nullable()->after('client_read_id');
            $table->unsignedBigInteger('admin_read_id')->nullable()->after('courier_read_id');
            $table->unsignedTinyInteger('rating')->nullable()->after('admin_read_id');
            $table->string('rating_comment', 500)->nullable()->after('rating');
            $table->timestamp('rated_at')->nullable()->after('rating_comment');
        });

        Schema::table('users', function (Blueprint $table) {
            // Dernière position connue du livreur, partagée uniquement pendant ses courses.
            $table->decimal('last_lat', 10, 7)->nullable()->after('vehicle');
            $table->decimal('last_lng', 10, 7)->nullable()->after('last_lat');
            $table->timestamp('located_at')->nullable()->after('last_lng');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['last_lat', 'last_lng', 'located_at']);
        });
        Schema::table('deliveries', function (Blueprint $table) {
            $table->dropColumn([
                'dropoff_code', 'last_message_id', 'client_read_id', 'courier_read_id', 'admin_read_id',
                'rating', 'rating_comment', 'rated_at',
            ]);
        });
        Schema::dropIfExists('delivery_messages');
    }
};
