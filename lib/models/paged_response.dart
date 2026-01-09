class PagedResponse<T> {
  final int total;
  final List<T> data;

  PagedResponse({required this.total, required this.data});

  factory PagedResponse.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) itemFromJson) {
    final total = json['total'] as int? ?? json['count'] as int? ?? 0;
    final items = (json['data'] as List<dynamic>? ?? []).map((e) => itemFromJson(Map<String, dynamic>.from(e as Map))).toList();
    return PagedResponse(total: total, data: items);
  }
}
