<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Compte supprimé par son titulaire (données personnelles anonymisées, historique conservé).
        Schema::table('users', function (Blueprint $table) {
            $table->timestamp('anonymized_at')->nullable()->after('is_active');
        });

        // Emails en minuscules, sauf si deux comptes ne diffèrent que par la casse (laissés tels quels).
        DB::statement(<<<'SQL'
            update users set email = lower(email)
            where email is not null and email <> lower(email)
              and not exists (select 1 from users u2 where u2.id <> users.id and lower(u2.email) = lower(users.email))
        SQL);
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('anonymized_at');
        });
    }
};
