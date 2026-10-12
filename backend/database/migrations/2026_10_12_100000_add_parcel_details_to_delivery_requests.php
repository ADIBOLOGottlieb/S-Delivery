<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/** Programmation par photo : quartier, numéro du destinataire et montant total du colis (obligatoires). */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('delivery_requests', function (Blueprint $table) {
            $table->string('district', 120)->nullable()->after('status');
            $table->string('recipient_phone', 30)->nullable()->after('district');
            $table->unsignedInteger('parcel_amount')->nullable()->after('recipient_phone');
        });
    }

    public function down(): void
    {
        Schema::table('delivery_requests', function (Blueprint $table) {
            $table->dropColumn(['district', 'recipient_phone', 'parcel_amount']);
        });
    }
};
