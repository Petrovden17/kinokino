class UserProfile {
  const UserProfile({
    required this.id, required this.name, required this.isChild,
    required this.passwordSalt, required this.passwordHash,
    required this.recoverySalt, required this.recoveryHash,
    this.pinSalt, this.pinHash,
  });
  final String id, name;
  final bool isChild;
  final String passwordSalt, passwordHash, recoverySalt, recoveryHash;
  final String? pinSalt, pinHash;

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'isChild': isChild,
    'passwordSalt': passwordSalt, 'passwordHash': passwordHash,
    'recoverySalt': recoverySalt, 'recoveryHash': recoveryHash,
    'pinSalt': pinSalt, 'pinHash': pinHash,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String, name: json['name'] as String,
    isChild: json['isChild'] as bool,
    passwordSalt: json['passwordSalt'] as String,
    passwordHash: json['passwordHash'] as String,
    recoverySalt: json['recoverySalt'] as String,
    recoveryHash: json['recoveryHash'] as String,
    pinSalt: json['pinSalt'] as String?, pinHash: json['pinHash'] as String?,
  );
}
