import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';
import '../api_client.dart';
import 'dart:typed_data';

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
  
  /// Save a bytes list (Excel file) to the local machine using a "Save As" dialog
  Future<void> saveLocalExcel(Uint8List bytes, String fileName) async {
    const String mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    final FileSaveLocation? result = await getSaveLocation(suggestedName: fileName);
    
    if (result != null) {
      final XFile xFile = XFile.fromData(bytes, mimeType: mimeType, name: fileName);
      await xFile.saveTo(result.path);
    }
  }

  /// Upload an Excel file (bytes) to the order's attachments
  Future<ApiResult> uploadExcel(int idnbr, Uint8List bytes, String fileName) async {
    return await client.postMultipart(
      '/orderops/serigrafia/upload-excel',
      files: [
        MultipartAttachment(
          fieldName: 'file',
          bytes: bytes,
          fileName: fileName,
        ),
      ],
      fields: {
        'idnbr': idnbr.toString(),
      },
    );
  }

  /// Fetch standards from the backend
  Future<List<SerigrafiaStandard>> getStandards() async {
    final res = await client.get('/orderops/serigrafia/standards');
    if (res.ok && res.body != null) {
      final data = res.body;
      List<dynamic> results = [];
      if (data is Map && data.containsKey('results')) {
        results = data['results'] as List? ?? [];
      } else if (data is List) {
        results = data;
      }
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
  Future<List<Map<String, dynamic>>> getRegistries(int idnbr, {String? labelName, bool includeProject = false}) async {
    final query = 'idnbr=$idnbr${labelName != null ? '&label_name=$labelName' : ''}${includeProject ? '&include_project=true' : ''}';
    final res = await client.get('/orderops/serigrafia/registries?$query');
    if (res.ok && res.body != null) {
      final data = res.body;
      List<dynamic> results = [];
      if (data is Map && data.containsKey('results')) {
        results = data['results'] as List? ?? [];
      } else if (data is List) {
        results = data;
      }
      return results.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  /// Update an existing registry record
  Future<ApiResult> updateRegistry(int id, Map<String, dynamic> data) async {
    return await client.put('/orderops/serigrafia/registry/$id', jsonBody: data);
  }

  /// Delete a registry record
  Future<ApiResult> deleteRegistry(int id) async {
    return await client.delete('/orderops/serigrafia/registry/$id');
  }

  /// Download Excel attachment and parse headers
  Future<Excel?> downloadAndParseExcel(String filePath) async {
    try {
      // Ensure we hit the /uploads/ endpoint instead of the /api/ endpoint
      final cleanPath = filePath.startsWith('/') ? filePath.substring(1) : filePath;
      
      // The client already prepends kBackendBaseUrl, so we only provide the relative path
      final cacheBuster = DateTime.now().millisecondsSinceEpoch;
      final res = await client.getBytes('/uploads/$cleanPath?t=$cacheBuster');
      
      if (!res.ok || res.body == null) {
        throw Exception('Download failed with status ${res.statusCode}');
      }
      
      debugPrint('SerigrafiaService: File downloaded, size: ${(res.body as List).length} bytes');
      final bytes = (res.body as List).cast<int>();
      
      debugPrint('SerigrafiaService: Decoding Excel...');
      final excel = Excel.decodeBytes(bytes);
      debugPrint('SerigrafiaService: Excel decoded. Sheets: ${excel.sheets.keys.toList()}');
      return excel;
    } catch (e, stack) {
      debugPrint('SerigrafiaService Error during downloadAndParse: $e');
      debugPrint('Stack trace: $stack');
      rethrow;
    }
  }

  /// Fetch headers from the first sheet (Row 1)
  List<String> getExcelHeaders(Excel excel) {
    try {
      // excel package 4.x uses 'sheets' as the primary map
      final sheets = excel.sheets;
      if (sheets.isEmpty) {
        debugPrint('SerigrafiaService: No sheets found in Excel');
        return [];
      }
      
      final sheetName = sheets.keys.first;
      final sheet = sheets[sheetName];
      if (sheet == null) {
        debugPrint('SerigrafiaService: Sheet "$sheetName" is null');
        return [];
      }
      
      if (sheet.maxRows == 0) {
        debugPrint('SerigrafiaService: Sheet "$sheetName" is empty (maxRows=0)');
        return [];
      }
      
      final rows = sheet.rows;
      if (rows.isEmpty) {
        debugPrint('SerigrafiaService: Sheet "$sheetName" has no rows');
        return [];
      }
      
      final firstRow = rows.first;
      return firstRow.map((cell) {
        if (cell == null) return '';
        final val = cell.value;
        if (val == null) return '';
        return val.toString().trim();
      }).toList();
    } catch (e) {
      debugPrint('SerigrafiaService: Error getting headers: $e');
      return [];
    }
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
