<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Throwable;

/**
 * Image envoyée par un utilisateur (profil, articles, chat), stockée en base.
 * Servie publiquement par son UUID (non devinable) : GET /media/{uuid}.
 *
 * La colonne « data » (base64, plusieurs Mo) n'est jamais chargée par défaut :
 * une liste de livraisons avec photos ne lit que l'uuid. bytes() la relit à la demande.
 */
class Media extends Model
{
    /** Colonnes lues par défaut (tout sauf data). */
    public const LIGHT_COLUMNS = ['id', 'uuid', 'mime', 'size', 'created_at', 'updated_at'];

    /** Côté le plus long après réduction. */
    private const MAX_SIDE = 1600;

    private const JPEG_QUALITY = 80;

    /** En dessous (et sous MAX_SIDE), l'image est gardée telle quelle. */
    private const KEEP_BELOW_BYTES = 400 * 1024;

    /** Au-delà, GD consommerait trop de mémoire : on garde l'original. */
    private const MAX_PIXELS = 40_000_000;

    protected $hidden = ['data'];

    protected static function booted(): void
    {
        // Sans select explicite, on lit toutes les colonnes sauf data (préfixées : jointure du pivot delivery_photos).
        static::addGlobalScope('without_data', function (Builder $query) {
            if ($query->getQuery()->columns === null) {
                $query->select(array_map(fn ($c) => 'media.'.$c, self::LIGHT_COLUMNS));
            }
        });
    }

    public static function fromUpload(UploadedFile $file): self
    {
        [$bytes, $mime] = self::shrink($file->getContent(), $file->getMimeType() ?: 'image/jpeg', $file->getRealPath() ?: null);

        $media = new self;
        $media->uuid = (string) Str::uuid();
        $media->mime = $mime;
        $media->size = strlen($bytes);
        $media->data = base64_encode($bytes);
        $media->save();

        return $media;
    }

    public function url(): string
    {
        return route('media.show', $this->uuid);
    }

    public function bytes(): string
    {
        $data = array_key_exists('data', $this->getAttributes())
            ? $this->getAttribute('data')
            : static::withoutGlobalScope('without_data')->whereKey($this->getKey())->value('data');

        return base64_decode((string) $data);
    }

    /**
     * Photo de téléphone (souvent 3 à 7 Mo) : réduite à 1600 px et recompressée en JPEG 80.
     * Gardée telle quelle si GD est absent, si l'image est déjà petite ou en cas d'échec.
     *
     * @return array{0: string, 1: string} octets et type MIME
     */
    private static function shrink(string $bytes, string $mime, ?string $path): array
    {
        if (! function_exists('imagecreatefromstring') || ! str_starts_with($mime, 'image/') || $mime === 'image/gif') {
            return [$bytes, $mime];
        }

        $info = @getimagesizefromstring($bytes);
        if (! $info || $info[0] < 1 || $info[1] < 1 || $info[0] * $info[1] > self::MAX_PIXELS) {
            return [$bytes, $mime];
        }
        [$width, $height] = $info;
        if (max($width, $height) <= self::MAX_SIDE && strlen($bytes) <= self::KEEP_BELOW_BYTES) {
            return [$bytes, $mime];
        }

        try {
            $source = @imagecreatefromstring($bytes);
            if ($source === false) {
                return [$bytes, $mime];
            }
            $source = self::applyExifOrientation($source, $mime, $path);
            $width = imagesx($source);
            $height = imagesy($source);

            $scale = min(1, self::MAX_SIDE / max($width, $height));
            $newWidth = max(1, (int) round($width * $scale));
            $newHeight = max(1, (int) round($height * $scale));

            // Fond blanc : la transparence d'un PNG ne devient pas noire en JPEG.
            $target = imagecreatetruecolor($newWidth, $newHeight);
            imagefill($target, 0, 0, imagecolorallocate($target, 255, 255, 255));
            imagecopyresampled($target, $source, 0, 0, 0, 0, $newWidth, $newHeight, $width, $height);
            unset($source); // libère la mémoire (imagedestroy est obsolète depuis PHP 8.5)

            ob_start();
            imagejpeg($target, null, self::JPEG_QUALITY);
            $jpeg = (string) ob_get_clean();
            unset($target);

            // Recompression inutile (image déjà optimisée et pas réduite) : on garde l'original.
            if ($jpeg === '' || ($scale === 1 && strlen($jpeg) >= strlen($bytes))) {
                return [$bytes, $mime];
            }

            return [$jpeg, 'image/jpeg'];
        } catch (Throwable $e) {
            Log::warning('Réduction de l\'image impossible : original conservé', ['error' => $e->getMessage()]);

            return [$bytes, $mime];
        }
    }

    /** Les téléphones enregistrent la rotation dans l'EXIF, perdu au réencodage : on l'applique. */
    private static function applyExifOrientation(\GdImage $image, string $mime, ?string $path): \GdImage
    {
        if ($mime !== 'image/jpeg' || $path === null || ! function_exists('exif_read_data')) {
            return $image;
        }

        $orientation = (int) (@exif_read_data($path)['Orientation'] ?? 1);
        $angle = match ($orientation) {
            3 => 180,
            6 => -90,
            8 => 90,
            default => 0,
        };

        return $angle === 0 ? $image : (imagerotate($image, $angle, 0) ?: $image);
    }
}
