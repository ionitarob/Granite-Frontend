class Smartphone {
  final Map<String, dynamic> _raw;
  Smartphone._(this._raw);

  factory Smartphone.fromJson(Map<String, dynamic> json) => Smartphone._(Map<String, dynamic>.from(json));

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(_raw);
}
