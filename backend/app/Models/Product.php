<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Support\Facades\Storage;

/** Produit de la marketplace, ou pack (type = pack) composé de plusieurs produits. */
#[Fillable([
    'category', 'subcategory_id', 'type', 'name', 'description', 'price', 'unit', 'image_path',
    'vendor_name', 'pickup_address', 'pickup_lat', 'pickup_lng', 'is_active',
])]
class Product extends Model
{
    use HasFactory;

    public const CATEGORIES = [
        'agro' => 'Courses alimentaires',
    ];

    protected $attributes = ['type' => 'product'];

    protected function casts(): array
    {
        return [
            'price' => 'integer',
            'pickup_lat' => 'float',
            'pickup_lng' => 'float',
            'is_active' => 'boolean',
        ];
    }

    public function isPack(): bool
    {
        return $this->type === 'pack';
    }

    public function subcategory(): BelongsTo
    {
        return $this->belongsTo(Subcategory::class);
    }

    /** Contenu d'un pack : produits et quantités. */
    public function packItems(): BelongsToMany
    {
        return $this->belongsToMany(Product::class, 'pack_items', 'pack_id', 'product_id')->withPivot('quantity');
    }

    /**
     * Photo du produit : envoyée par l'admin (disque public), ou photo du catalogue de départ
     * livrée avec l'application (public/images/catalog, préfixe « catalog/ ») qui survit aux redéploiements.
     */
    public function imageUrl(): ?string
    {
        if (! $this->image_path) {
            return null;
        }

        return str_starts_with($this->image_path, 'catalog/')
            ? asset('images/'.$this->image_path)
            : Storage::disk('public')->url($this->image_path);
    }

    public function hasUploadedImage(): bool
    {
        return $this->image_path !== null && ! str_starts_with($this->image_path, 'catalog/');
    }
}
