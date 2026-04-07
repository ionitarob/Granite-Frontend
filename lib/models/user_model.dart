class User {
  final String username;
  final String role;
  // prefer the backend-provided Spanish field `nombre` when present
  final String? nombre;

  User({required this.username, required this.role, this.nombre});
  
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      nombre: json['nombre']?.toString(),
    );
  }

  String displayName() => (nombre != null && nombre!.isNotEmpty) ? nombre! : username;
}
