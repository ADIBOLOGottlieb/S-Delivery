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
        'shopping' => 'Shopping',
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

    public function imageUrl(): ?string
    {
        return $this->image_path ? Storage::disk('public')->url($this->image_path) : null;
    }
}
