import 'dart:convert';
import 'package:excel/excel.dart';
import '../api_client.dart';

class SerigrafiaStandard {
  final int? id;
  final String name;
  final String url;
  final List<String> variables;

  SerigrafiaStandard({
    this.id,
    required this.name,
    required this.url,
    required this.variables,
  });

  factory SerigrafiaStandard.fromJson(Map<String, dynamic> json) {
    return SerigrafiaStandard(
      id: json['id'] as int?,
      name: json['name'] as String,
      url: json['url'] as String,
      variables: List<String>.from(json['variables'] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'variables': variables,
  };
}

class SerigrafiaService {
  final ApiClient client;

  SerigrafiaService(this.client);

  /// Fetch standards from the backend
  Future<List<SerigrafiaStandard>> getStandards() async {
    final res = await client.get('/orderops/serigrafia/standards');
    if (res.ok && res.body != null) {
       final results = res.body?['results'] as List? ?? res.body as List? ?? [];
       return results.map((j) => SerigrafiaStandard.fromJson(j)).toList();
    }
    return []; // Fallback to empty
  }

  /// Save (Create or Update) a standard
  Future<ApiResult> saveStandard(SerigrafiaStandard s) async {
    if (s.id != null) {
      return await client.put('/orderops/serigrafia/standards/${s.id}', jsonBody: s.toJson());
    } else {
      return await client.post('/orderops/serigrafia/standards', jsonBody: s.toJson());
    }
  }

  /// Delete a standard
  Future<ApiResult> deleteStandard(int id) async {
    return await client.delete('/orderops/serigrafia/standards/$id');
  }

  /// Save scan/print registration to database
  Future<ApiResult> saveRegistry(
    int idnbr,
    String labelName,
    Map<String, String> data, {
    String? operator,
  }) async {
    print('[SerigrafiaService] 💾 Saving registry: order=$idnbr, label=$labelName, operator=$operator');
    
    // Extract CI and Serial from data for dedicated columns
    String? ci;
    String? serial;
    
    // Try common variations of CI field names
    for (final key in data.keys) {
      if (key.toUpperCase() == 'CI' || key.toUpperCase() == 'CI_CODE') {
        ci = data[key];
      }
      if (key.toUpperCase() == 'SERIAL') {
        serial = data[key];
      }
    }
    
    final payload = {
      'idnbr': idnbr,
      'label_name': labelName,
      'data': jsonEncode(data), // Ensure data is JSON string, not a nested object
      if (operator != null) 'operator': operator,
      if (ci != null) 'ci': ci,
      if (serial != null) 'serial': serial,
    };
    
    print('[SerigrafiaService] 📤 Registry payload: $payload');
    
    final res = await client.post('/orderops/serigrafia/registry', jsonBody: payload);
    
    if (res.ok) {
      print('[SerigrafiaService] ✅ Registry saved successfully (CI: $ci, Serial: $serial)');
    } else {
      print('[SerigrafiaService] ❌ Failed to save registry: ${res.error}');
    }
    
    return res;
  }

  /// List scan/print registrations for an order/project
  Future<List<Map<String, dynamic>>> getRegistries(int idnbr, {String? labelName}) async {
    final query = 'idnbr=$idnbr${labelName != null ? '&label_name=$labelName' : ''}';
    final res = await client.get('/orderops/serigrafia/registries?$query');
    if (res.ok && res.body != null) {
      final results = res.body['results'] as List? ?? [];
      return results.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  /// Download Excel attachment and parse headers
  Future<Excel?> downloadAndParseExcel(String filePath) async {
    try {
      // Ensure we hit the /uploads/ endpoint instead of the /api/ endpoint
      final cleanPath = filePath.startsWith('/') ? filePath.substring(1) : filePath;
      
      // The client already prepends kBackendBaseUrl, so we only provide the relative path
      final res = await client.getBytes('/uploads/$cleanPath');
      
      if (!res.ok || res.body == null) {
        throw Exception('Download failed with status ${res.statusCode}');
      }
      
      final bytes = (res.body as List).cast<int>();
      return Excel.decodeBytes(bytes);
    } catch (e) {
      print('Excel Parsing error: $e');
      rethrow;
    }
  }

  /// Fetch headers from the first sheet (Row 1)
  List<String> getExcelHeaders(Excel excel) {
    final sheet = excel.tables.values.first;
    if (sheet.maxRows == 0) return [];
    final firstRow = sheet.rows.first;
    return firstRow.map((cell) => cell?.value?.toString() ?? '').toList();
  }

  /// Print a row using the specified standard and variable mapping
  Future<ApiResult> printLabel(
    SerigrafiaStandard standard,
    Map<String, String> variableValues,
  ) async {
    final isAbsoluteUrl = standard.url.startsWith('http://') || standard.url.startsWith('https://');

    if (isAbsoluteUrl) {
      // Route external BarTender calls through backend so Integration Builder
      // receives requests from the server environment (same as other modules).
      return await client.post(
        '/orderops/serigrafia/print',
        jsonBody: {
          'url': standard.url,
          'label_name': standard.name,
          // Keep legacy nested payload and also flatten variables at root
          // to match Amazon batch style (direct JSON fields).
          'data': variableValues,
          ...variableValues,
        },
      );
    } else {
      // For relative paths, use the ApiClient (prepends baseUrl)
      print('[SerigrafiaService] 🔗 Sending to API endpoint: ${standard.url}');
      return await client.post(
        standard.url,
        jsonBody: variableValues,
      );
    }
  }

  /// Fetch the next available inventory code (CI)
  Future<String?> getNextInventoryCode() async {
    final res = await client.get('/serials/claim');
    if (res.ok && res.body != null) {
      return res.body?['inventory_code'] as String?;
    }
    return null;
  }

  /// Finalize the claim by linking a serial to an inventory code
  Future<bool> finalizeInventoryClaim(String code, String serial) async {
    final res = await client.post(
      '/serials/finalize',
      jsonBody: {
        'inventory_code': code,
        'real_serial': serial,
      },
    );
    return res.ok;
  }
}
