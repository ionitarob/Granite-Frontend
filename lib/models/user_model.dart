class User {
  final int? id;
  final String username;
  final String role;
  // prefer the backend-provided Spanish field `nombre` when present
  final String? nombre;

  User({this.id, required this.username, required this.role, this.nombre});
  
  factory User.fromJson(Map<String, dynamic> json) {
    int? parsedId;
    final idRaw = json['id'] ?? json['user_id'];
    if (idRaw != null) {
      if (idRaw is int) {
        parsedId = idRaw;
      } else if (idRaw is String) {
        parsedId = int.tryParse(idRaw);
      } else if (idRaw is double) {
        parsedId = idRaw.toInt();
      }
    }

    return User(
      id: parsedId,
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      nombre: json['nombre']?.toString(),
    );
  }

  String displayName() => (nombre != null && nombre!.isNotEmpty) ? nombre! : username;
}
