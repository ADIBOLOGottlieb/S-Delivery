class UserRole {
  static const client = 'client';
  static const courier = 'livreur';
  static const admin = 'admin';
}

class User {
  final int id;
  final String name;
  final String? email;
  final String phoneNumber;
  final String role;
  final String? vehicle;

  /// Quartier (renseigné par l'agence pour ses anciens clients).
  final String? district;

  /// Photo de profil (URL publique servie par l'API), null si aucune.
  final String? avatarUrl;

  /// Client habitué : peut commander par simple envoi de photos (demande rapide + chat).
  final bool isRegular;

  const User({
    required this.id,
    required this.name,
    this.email,
    required this.phoneNumber,
    required this.role,
    this.vehicle,
    this.district,
    this.avatarUrl,
    this.isRegular = false,
  });

  bool get isCourier => role == UserRole.courier;
  bool get isClient => role == UserRole.client;

  String get roleLabel => switch (role) {
        UserRole.courier => 'Livreur',
        UserRole.admin => 'Administrateur',
        _ => isRegular ? 'Client fidèle' : 'Client',
      };

  String get initial => name.trim().isEmpty ? 'U' : name.trim()[0].toUpperCase();

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        name: json['name'] as String,
        email: json['email'] as String?,
        phoneNumber: json['phone_number'] as String,
        role: json['role'] as String,
        vehicle: json['vehicle'] as String?,
        district: json['district'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        isRegular: json['is_regular'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone_number': phoneNumber,
        'role': role,
        'vehicle': vehicle,
        'district': district,
        'avatar_url': avatarUrl,
        'is_regular': isRegular,
      };
}
