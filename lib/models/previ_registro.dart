class PreviRegistro {
  final int? id;
  final String previ;
  final String cliente;
  final String? expediente;
  final String operario;
  final String? operariosSoporte;
  final String descripcion;
  final DateTime? fecha;
  final String? user;
  final List<String> images;

  PreviRegistro({
    this.id,
    required this.previ,
    required this.cliente,
    this.expediente,
    required this.operario,
    this.operariosSoporte,
    required this.descripcion,
    this.fecha,
    this.user,
    List<String>? images,
  }) : images = images ?? const [];

  Map<String, String> toFields() => {
        'previ': previ,
        'cliente': cliente,
        'expediente': expediente ?? '',
        'operario': operario,
        'opsoporte': operariosSoporte ?? '',
        'desc': descripcion,
      };

  factory PreviRegistro.fromJson(Map<String, dynamic> json) => PreviRegistro(
        id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? ''),
        previ: json['previ'] ?? '',
        cliente: json['cliente'] ?? '',
        expediente: json['expediente']?.toString(),
        operario: json['operario'] ?? '',
        operariosSoporte: json['opsoporte']?.toString(),
        descripcion: json['desc'] ?? json['descripción'] ?? '',
        fecha: json['fecha'] != null ? DateTime.tryParse(json['fecha']) : null,
        user: json['user']?.toString(),
        images: (json['images'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}
