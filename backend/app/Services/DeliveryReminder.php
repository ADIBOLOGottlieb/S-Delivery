<?php

namespace App\Services;

use App\Enums\DeliveryStatus;
use App\Enums\DeliveryType;
use App\Models\Delivery;
use App\Models\User;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Notifications liées aux livraisons : nouvelle course et rappels pour le livreur,
 * suivi (paiement, livreur, colis) pour le client. Un push raté ne bloque jamais l'action.
 */
class DeliveryReminder
{
    /** Une livraison dont l'heure limite tombe dans ce délai est considérée urgente. */
    public const URGENT_WITHIN_MINUTES = 45;

    /** Intervalle minimal entre deux rappels pour une même livraison. */
    public const REMIND_EVERY_MINUTES = 10;

    public function __construct(private readonly PushNotifier $push) {}

    public static function isUrgent(Delivery $delivery): bool
    {
        return $delivery->type === DeliveryType::Express
            || ($delivery->deadline_at && $delivery->deadline_at->lte(now()->addMinutes(self::URGENT_WITHIN_MINUTES)));
    }

    public function notifyAssigned(Delivery $delivery): void
    {
        $courier = $delivery->courier;
        if (! $courier) {
            return;
        }

        $urgent = self::isUrgent($delivery);
        $this->send(
            $courier,
            ($urgent ? '⚡ URGENT · ' : '').'Nouvelle livraison '.$delivery->reference,
            'Récupération : '.$delivery->pickup_address.$this->deadlineText($delivery),
            [...self::data($delivery), 'kind' => 'assigned'],
            $urgent,
        );
    }

    /** Course retirée au livreur : annulée par l'agence ou confiée à un autre. */
    public function notifyCourierRemoved(Delivery $delivery, ?User $courier, string $kind): void
    {
        if (! $courier) {
            return;
        }

        [$title, $body] = $kind === 'cancelled'
            ? ['Course annulée '.$delivery->reference, "La livraison {$delivery->reference} a été annulée par l'agence. Ne vous déplacez pas."]
            : ['Course retirée '.$delivery->reference, "La livraison {$delivery->reference} a été confiée à un autre livreur."];

        $this->send($courier, $title, $body, [...self::data($delivery), 'kind' => $kind]);
    }

    /**
     * Suivi côté client.
     *
     * @param  string  $event  payment_verified | payment_rejected | assigned | picked_up | delivered | cancelled
     */
    public function notifyClient(Delivery $delivery, string $event, ?string $detail = null): void
    {
        $client = $delivery->client;
        if (! $client) {
            return;
        }

        $ref = $delivery->reference;
        [$title, $body] = match ($event) {
            'payment_verified' => ['Paiement confirmé ✅', "Votre paiement pour la livraison {$ref} est confirmé. Un livreur va être assigné."],
            'payment_rejected' => ['Paiement refusé', "Le paiement de la livraison {$ref} a été refusé : {$detail}. Renvoyez une preuve depuis l'application."],
            'assigned' => ['Livreur assigné 🛵', ($delivery->courier?->name ?? 'Un livreur')." s'occupe de votre livraison {$ref}."],
            'picked_up' => ['Colis récupéré', "Votre colis {$ref} a été récupéré et est en route."],
            'delivered' => ['Colis livré ✅', "La livraison {$ref} est terminée. Merci d'avoir choisi S-Delivery !"],
            'cancelled' => ['Livraison annulée', "La livraison {$ref} a été annulée par l'agence".($detail ? " : {$detail}" : '').'.'
                .($delivery->needsRefund() ? ' Votre paiement vous sera remboursé.' : '')],
        };

        $this->send($client, $title, $body, self::data($delivery));
    }

    /**
     * Rappels pour les livraisons urgentes en cours (Express ou heure limite proche/dépassée).
     *
     * @return int nombre de rappels envoyés
     */
    public function sendDueReminders(): int
    {
        // Deux appels simultanés (GitHub + cron-job.org) n'envoient pas deux fois les mêmes rappels.
        $lock = Cache::lock('delivery-reminders', 120);
        if (! $lock->get()) {
            return 0;
        }

        try {
            return $this->sendDueRemindersUnlocked();
        } finally {
            $lock->release();
        }
    }

    private function sendDueRemindersUnlocked(): int
    {
        $sent = 0;

        Delivery::query()
            ->with('courier')
            ->whereIn('status', [DeliveryStatus::Assigned, DeliveryStatus::PickedUp])
            ->whereNotNull('courier_id')
            ->where(fn ($q) => $q
                ->where('type', DeliveryType::Express)
                ->orWhere('deadline_at', '<=', now()->addMinutes(self::URGENT_WITHIN_MINUTES)))
            ->where(fn ($q) => $q
                ->whereNull('last_reminder_at')
                ->orWhere('last_reminder_at', '<=', now()->subMinutes(self::REMIND_EVERY_MINUTES)))
            ->each(function (Delivery $delivery) use (&$sent) {
                $late = $delivery->deadline_at?->isPast();
                $step = $delivery->status === DeliveryStatus::Assigned ? 'Colis à récupérer' : 'Colis à livrer';

                $ok = $this->send(
                    $delivery->courier,
                    ($late ? '⏰ EN RETARD · ' : '⚡ Urgent · ').$delivery->reference,
                    $step.' : '.($delivery->status === DeliveryStatus::Assigned ? $delivery->pickup_address : $delivery->dropoff_address)
                        .$this->deadlineText($delivery),
                    [...self::data($delivery), 'kind' => 'reminder'],
                    true,
                );

                $delivery->forceFill(['last_reminder_at' => now()])->saveQuietly();
                $sent += $ok ? 1 : 0;
            });

        return $sent;
    }

    /** @return array{type: string, delivery_id: string} ouvre la livraison dans l'app */
    private static function data(Delivery $delivery): array
    {
        return ['type' => 'delivery', 'delivery_id' => (string) $delivery->id];
    }

    /** @param array<string, string> $data */
    private function send(User $user, string $title, string $body, array $data, bool $urgent = false): bool
    {
        try {
            return $this->push->toUser($user, $title, $body, $data, $urgent);
        } catch (Throwable $e) {
            Log::warning('Push livraison non envoyé', ['user_id' => $user->id, 'error' => $e->getMessage()]);

            return false;
        }
    }

    private function deadlineText(Delivery $delivery): string
    {
        return $delivery->deadline_at
            ? ' · avant '.$delivery->deadline_at->timezone(config('app.timezone'))->format('H:i')
            : '';
    }
}
