<?php

namespace App\Support;

use App\Models\Media;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;

/**
 * Images envoyées par l'admin (produits, annonces), stockées en base (table media) :
 * le disque de Render est effacé à chaque redéploiement.
 * Chemins acceptés : « media/<uuid> » (base), « catalog/… » (photos livrées avec l'app),
 * ou un ancien fichier du disque public.
 */
class StoredImage
{
    private const PREFIX = 'media/';

    public static function store(UploadedFile $file): string
    {
        return self::PREFIX.Media::fromUpload($file)->uuid;
    }

    public static function url(?string $path): ?string
    {
        return match (true) {
            $path === null || $path === '' => null,
            str_starts_with($path, self::PREFIX) => route('media.show', substr($path, strlen(self::PREFIX))),
            str_starts_with($path, 'catalog/') => asset('images/'.$path),
            default => Storage::disk('public')->url($path),
        };
    }

    /** Supprime une image envoyée (jamais une photo du catalogue de départ). */
    public static function delete(?string $path): void
    {
        if ($path === null || $path === '' || str_starts_with($path, 'catalog/')) {
            return;
        }
        if (str_starts_with($path, self::PREFIX)) {
            Media::where('uuid', substr($path, strlen(self::PREFIX)))->delete();

            return;
        }
        Storage::disk('public')->delete($path);
    }
}
