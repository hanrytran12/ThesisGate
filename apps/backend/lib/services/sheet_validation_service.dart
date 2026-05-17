import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:googleapis/sheets/v4.dart' as gs;
import 'package:googleapis_auth/auth_io.dart';

import '../models/sheet_validation_models.dart';

class SheetValidationService {
  static const Map<String, List<String>> _requiredColumnsBySheetName = {
    'THESIS_INFO': [
      'thesis_id',
      'vietnamese_title',
      'english_title',
      'supervisor',
    ],
    'STUDENTS': [
      'thesis_id',
      'student_id',
      'full_name',
      'major',
    ],
    'EVALUATION': [
      'thesis_id',
      'content_review',
      'format_review',
      'attitude_review',
      'achievement_level',
      'limitation',
    ],
    'DEFENSE_RESULT': [
      'thesis_id',
      'student_id',
      'defense_result',
      'note',
    ],
  };

  SheetParseResult parseSheetUrl(String sheetUrl) {
    final uri = Uri.tryParse(sheetUrl);
    if (uri == null || uri.host != 'docs.google.com') {
      throw const FormatException('URL Google Sheet không hợp lệ.');
    }

    final segments = uri.pathSegments;
    final dIndex = segments.indexOf('d');
    if (dIndex == -1 || dIndex + 1 >= segments.length) {
      throw const FormatException('Không tìm thấy spreadsheetId trong URL.');
    }

    final spreadsheetId = segments[dIndex + 1];
    if (spreadsheetId.isEmpty) {
      throw const FormatException('spreadsheetId rỗng.');
    }

    return SheetParseResult(spreadsheetId: spreadsheetId);
  }

  Future<SheetValidationResult> validateFromUrl(String sheetUrl) async {
    final parsed = parseSheetUrl(sheetUrl);
    final sheetsApi = await _buildSheetsApi();

    final spreadsheet = await sheetsApi.spreadsheets.get(parsed.spreadsheetId);
    final existingSheetNames = (spreadsheet.sheets ?? [])
        .map((s) => s.properties?.title?.trim().toUpperCase())
        .whereType<String>()
        .toSet();

    final allErrors = <ValidationErrorItem>[];
    var totalRows = 0;
    var validRows = 0;
    var invalidRows = 0;

    for (final entry in _requiredColumnsBySheetName.entries) {
      final sheetName = entry.key;

      if (!existingSheetNames.contains(sheetName)) {
        allErrors.add(
          ValidationErrorItem(
            sheetName: sheetName,
            code: 'SHEET_NOT_FOUND',
            message: 'Không tìm thấy sheet [$sheetName] trong file.',
            column: '__sheet__',
          ),
        );
        continue;
      }

      final values = await _readSheetValues(sheetsApi, parsed.spreadsheetId, sheetName);
      final rows = values
          .map((row) => row.map((cell) => cell.toString().trim()).toList())
          .toList();

      final result = _validateRows(rows, sheetName: sheetName);
      totalRows += result.summary.totalRows;
      validRows += result.summary.validRows;
      invalidRows += result.summary.invalidRows;
      allErrors.addAll(result.errors);
    }

    return SheetValidationResult(
      ok: allErrors.isEmpty,
      summary: ValidationSummary(
        totalRows: totalRows,
        validRows: validRows,
        invalidRows: invalidRows,
      ),
      errors: allErrors,
    );
  }

  Future<gs.SheetsApi> _buildSheetsApi() async {
    final credentialsPath = _resolveCredentialsPath();

    final file = File(credentialsPath);
    if (!await file.exists()) {
      throw StateError('Không tìm thấy credentials file tại: $credentialsPath');
    }

    final jsonMap = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final accountCredentials = ServiceAccountCredentials.fromJson(jsonMap);

    final client = await clientViaServiceAccount(
      accountCredentials,
      [gs.SheetsApi.spreadsheetsReadonlyScope],
    );

    return gs.SheetsApi(client);
  }

  String _resolveCredentialsPath() {
    final fromOs = Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'];
    if (fromOs != null && fromOs.trim().isNotEmpty) return fromOs.trim();

    // Fallback: đọc .env thủ công từ working directory (apps/backend)
    final envFile = File('.env');
    if (envFile.existsSync()) {
      final lines = envFile.readAsLinesSync();
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        if (!line.startsWith('GOOGLE_APPLICATION_CREDENTIALS=')) continue;

        var value = line.substring('GOOGLE_APPLICATION_CREDENTIALS='.length).trim();
        if ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }
        if (value.isNotEmpty) return value;
      }
    }

    throw StateError(
      'Thiếu GOOGLE_APPLICATION_CREDENTIALS. Hãy set env OS hoặc khai báo trong apps/backend/.env.',
    );
  }

  Future<List<List<Object?>>> _readSheetValues(
    gs.SheetsApi api,
    String spreadsheetId,
    String sheetName,
  ) async {
    final range = '$sheetName!A:ZZ';
    final response = await api.spreadsheets.values.get(spreadsheetId, range);
    return (response.values ?? []).map((row) => row.toList()).toList();
  }

  Future<List<String>> getSepTabsFromUrl(String sheetUrl) async {
    final parsed = parseSheetUrl(sheetUrl);
    final sheetsApi = await _buildSheetsApi();

    final spreadsheet = await sheetsApi.spreadsheets.get(parsed.spreadsheetId);
    final allNames = (spreadsheet.sheets ?? [])
        .map((s) => s.properties?.title?.trim())
        .whereType<String>()
        .toList();

    return allNames
        .where((name) => RegExp(r'^SEP490_[^_]+_.+', caseSensitive: false).hasMatch(name))
        .toList();
  }

  Future<Map<String, dynamic>> importFromUrl(String sheetUrl, {List<String>? sheetNames}) async {
    final parsed = parseSheetUrl(sheetUrl);
    final sheetsApi = await _buildSheetsApi();

    final matchedSepSheets = await getSepTabsFromUrl(sheetUrl);

    final targetSheets = (sheetNames != null && sheetNames.isNotEmpty)
        ? matchedSepSheets.where((s) => sheetNames.any((x) => x.toLowerCase() == s.toLowerCase())).toList()
        : matchedSepSheets;

    if (targetSheets.isEmpty) {
      return {
        'ok': false,
        'error': {
          'code': 'SHEET_NOT_FOUND',
          'message': sheetNames != null && sheetNames.isNotEmpty
              ? 'Không tìm thấy tab SEP490_* khớp với sheetNames yêu cầu.'
              : 'Không tìm thấy sheet dạng SEP490_<ma_lop>_... để import.',
        },
      };
    }

    final outputsDir = Directory(p.join(Directory.current.path, 'outputs', 'cmt'));
    if (!outputsDir.existsSync()) {
      outputsDir.createSync(recursive: true);
    }

    final results = <Map<String, dynamic>>[];

    for (final sepSheetName in targetSheets) {
      final sepRows = await _readSheetValues(sheetsApi, parsed.spreadsheetId, sepSheetName);
      final payload = {
        'spreadsheetId': parsed.spreadsheetId,
        'sheetName': sepSheetName,
        'students': sepRows,
      };

      final ts = DateTime.now().millisecondsSinceEpoch;
      final safeSheet = sepSheetName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

      // Write .cmt.json for AI evaluation/build-later flow
      final outputCmtJsonPath = p.join(outputsDir.path, 'sheet_import_${safeSheet}_$ts.cmt.json');
      final rawRows = payload['students'] as List;
      final cmtJsonStudents = <Map<String, dynamic>>[];
      if (rawRows.length > 1) {
        final hMap = <String, int>{};
        final headerRow = (rawRows[0] as List).map((e) => e.toString()).toList();
        for (var hi = 0; hi < headerRow.length; hi++) {
          hMap[_normalizeHeader(headerRow[hi])] = hi;
        }
        String colVal(List<String> row, List<String> keys) {
          for (final k in keys) {
            final idx = hMap[_normalizeHeader(k)];
            if (idx != null && idx < row.length) {
              final v = row[idx].trim();
              if (v.isNotEmpty) return v;
            }
          }
          return '';
        }
        for (var ri = 1; ri < rawRows.length; ri++) {
          final row = (rawRows[ri] as List).map((e) => e.toString()).toList();
          cmtJsonStudents.add({
            'roll':        colVal(row, ['Roll', 'roll', 'student_id', 'mã sv']),
            'name':        colVal(row, ['full_name', 'Họ tên sinh viên bảo vệ', 'họ tên']),
            'titleVN':     colVal(row, ['vietnamese_title', 'Tên khóa luận (Tiếng Việt)']),
            'titleEN':     colVal(row, ['english_title', 'Tên khóa luận (Tiếng Anh)']),
            'content':     colVal(row, ['content_review', 'Nhận xét GV về nội dung khóa luận']),
            'form':        colVal(row, ['format_review', 'Nhận xét GV về hình thức khóa luận']),
            'attitude':    colVal(row, ['attitude_review', 'Nhận xét GV về thái độ sinh viên']),
            'achievement': colVal(row, ['achievement_level', 'Kết luận - Mức độ đạt yêu cầu']),
            'limitation':  colVal(row, ['limitation', 'Kết luận - Hạn chế']),
          });
        }

        // Propagate thesis-level fields from first row to students with empty values
        // (Google Sheets merged cells only return a value in the first merged row)
        if (cmtJsonStudents.isNotEmpty) {
          final base = cmtJsonStudents.first;
          const thesisLevelFields = [
            'titleVN', 'titleEN', 'content', 'form',
            'achievement', 'limitation', 'attitude',
          ];
          for (var i = 1; i < cmtJsonStudents.length; i++) {
            final s = cmtJsonStudents[i];
            for (final field in thesisLevelFields) {
              if ((s[field] as String? ?? '').isEmpty &&
                  (base[field] as String? ?? '').isNotEmpty) {
                s[field] = base[field];
              }
            }
          }
        }
      }
      await File(outputCmtJsonPath).writeAsString(jsonEncode({
        'format':    'ThesisGate-CMT-v1',
        'sheetName': sepSheetName,
        'createdAt': DateTime.now().toIso8601String(),
        'students':  cmtJsonStudents,
      }));

      results.add({
        'ok': true,
        'sheetName': sepSheetName,
        'cmtJsonPath': outputCmtJsonPath,
      });
    }

    return {
      'ok': results.any((r) => r['ok'] == true),
      'spreadsheetId': parsed.spreadsheetId,
      'totalSheets': targetSheets.length,
      'successCount': results.where((r) => r['ok'] == true).length,
      'failedCount': results.where((r) => r['ok'] != true).length,
      'results': results,
    };
  }

  SheetValidationResult _validateRows(
    List<List<String>> rows, {
    required String sheetName,
  }) {
    final errors = <ValidationErrorItem>[];

    if (rows.isEmpty) {
      errors.add(
        ValidationErrorItem(
          code: 'EMPTY_SHEET',
          message: 'Sheet [$sheetName] không có dữ liệu.',
          sheetName: sheetName,
          column: '__sheet__',
        ),
      );
      return SheetValidationResult(
        ok: false,
        summary: ValidationSummary(totalRows: 0, validRows: 0, invalidRows: 0),
        errors: errors,
      );
    }

    final headers = rows.first.map(_normalizeHeader).toList();
    final headerIndex = <String, int>{};

    for (var i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (h.isEmpty) continue;
      if (headerIndex.containsKey(h)) {
        errors.add(
          ValidationErrorItem(
            code: 'DUPLICATE_HEADER',
            message: 'Sheet [$sheetName] header bị trùng: $h',
            sheetName: sheetName,
            column: h,
          ),
        );
      } else {
        headerIndex[h] = i;
      }
    }

    final requiredColumns = _requiredColumnsBySheetName[sheetName.trim().toUpperCase()]!;

    for (final col in requiredColumns) {
      if (!headerIndex.containsKey(col)) {
        errors.add(
          ValidationErrorItem(
            code: 'MISSING_REQUIRED_COLUMN',
            message: 'Sheet [$sheetName] thiếu cột bắt buộc: $col',
            sheetName: sheetName,
            column: col,
          ),
        );
      }
    }

    if (errors.isNotEmpty) {
      return SheetValidationResult(
        ok: false,
        summary: ValidationSummary(totalRows: 0, validRows: 0, invalidRows: 0),
        errors: errors,
      );
    }

    final dataRows = rows.skip(1).toList();
    var validRows = 0;
    var invalidRows = 0;

    final seenStudentIds = <String>{};
    final seenPairKeys = <String>{};

    for (var i = 0; i < dataRows.length; i++) {
      final row = dataRows[i];
      final rowNumber = i + 2;
      var rowHasError = false;

      String valueOf(String column) {
        final idx = headerIndex[column]!;
        if (idx >= row.length) return '';
        return row[idx].trim();
      }

      void addError(String code, String message, String column, String? value) {
        rowHasError = true;
        errors.add(
          ValidationErrorItem(
            rowNumber: rowNumber,
            column: column,
            sheetName: sheetName,
            code: code,
            message: message,
            value: value,
          ),
        );
      }

      for (final col in requiredColumns) {
        final value = valueOf(col);
        if (value.isEmpty) {
          addError('REQUIRED_MISSING', '$col không được rỗng', col, value);
        }
      }

      if (requiredColumns.contains('student_id')) {
        final studentId = valueOf('student_id');
        final studentIdPattern = RegExp(r'^[A-Za-z]{2}\d{6}$');

        if (studentId.isNotEmpty && !studentIdPattern.hasMatch(studentId)) {
          addError('INVALID_FORMAT', 'student_id sai định dạng', 'student_id', studentId);
        }

        if (studentId.isNotEmpty && seenStudentIds.contains(studentId)) {
          addError('DUPLICATE_STUDENT_ID', 'student_id bị trùng', 'student_id', studentId);
        }

        if (requiredColumns.contains('thesis_id')) {
          final thesisId = valueOf('thesis_id');
          final pairKey = '$thesisId|$studentId';
          if (thesisId.isNotEmpty && studentId.isNotEmpty && seenPairKeys.contains(pairKey)) {
            addError('DUPLICATE_THESIS_STUDENT', 'Cặp thesis_id + student_id bị trùng', 'thesis_id', thesisId);
          }

          if (!rowHasError && studentId.isNotEmpty) {
            seenStudentIds.add(studentId);
            seenPairKeys.add(pairKey);
          }
        }
      }

      if (!rowHasError) {
        validRows++;
      } else {
        invalidRows++;
      }
    }

    return SheetValidationResult(
      ok: errors.isEmpty,
      summary: ValidationSummary(
        totalRows: dataRows.length,
        validRows: validRows,
        invalidRows: invalidRows,
      ),
      errors: errors,
    );
  }

  String _normalizeHeader(String input) {
    return input.trim().toLowerCase().replaceAll(' ', '_');
  }
}
