class ServerRegistro {
  final String serverSerial; // S/N del servidor
  final List<PiezaRegistro> piezas;

  ServerRegistro({required this.serverSerial, List<PiezaRegistro>? piezas}) : piezas = piezas ?? [];

  bool get hasPiezas => piezas.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'server_serial': serverSerial,
        'piezas': piezas.map((p) => p.toJson()).toList(),
      };

  factory ServerRegistro.fromJson(Map<String, dynamic> json) => ServerRegistro(
        serverSerial: json['server_serial']?.toString() ?? json['serverSerial']?.toString() ?? '',
        piezas: (json['piezas'] as List?)?.map((entry) {
              if (entry is PiezaRegistro) return entry;
              if (entry is Map<String, dynamic>) return PiezaRegistro.fromJson(entry);
              if (entry is Map) return PiezaRegistro.fromJson(entry.map((k, v) => MapEntry(k.toString(), v)));
              return PiezaRegistro(pn: entry.toString(), sn: '');
            }).toList() ??
            const [],
      );

  ServerRegistro copyWith({String? serverSerial, List<PiezaRegistro>? piezas}) => ServerRegistro(
        serverSerial: serverSerial ?? this.serverSerial,
        piezas: piezas ?? List<PiezaRegistro>.from(this.piezas),
      );
}

class PiezaRegistro {
  String pn; // P/N
  String sn; // S/N
  PiezaRegistro({required this.pn, required this.sn});

  Map<String, String> toJson() => {'pn': pn, 'sn': sn};

  factory PiezaRegistro.fromJson(Map<String, dynamic> json) => PiezaRegistro(
        pn: json['pn']?.toString() ?? '',
        sn: json['sn']?.toString() ?? '',
      );
}
