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

  Future<Map<String, dynamic>> importFromUrl(String sheetUrl) async {
    final parsed = parseSheetUrl(sheetUrl);
    final sheetsApi = await _buildSheetsApi();

    final spreadsheet = await sheetsApi.spreadsheets.get(parsed.spreadsheetId);
    final allNames = (spreadsheet.sheets ?? [])
        .map((s) => s.properties?.title?.trim())
        .whereType<String>()
        .toList();

    final sepSheetName = allNames.firstWhere(
      (name) => RegExp(r'^SEP490_[^_]+_.+', caseSensitive: false).hasMatch(name),
      orElse: () => '',
    );

    if (sepSheetName.isEmpty) {
      return {
        'ok': false,
        'error': {
          'code': 'SHEET_NOT_FOUND',
          'message': 'Không tìm thấy sheet dạng SEP490_<ma_lop>_... để import.',
        },
      };
    }

    final sepRows = await _readSheetValues(sheetsApi, parsed.spreadsheetId, sepSheetName);

    final payload = {
      'spreadsheetId': parsed.spreadsheetId,
      'sheetName': sepSheetName,
      'students': sepRows,
    };

    final outputsDir = Directory(p.join(Directory.current.path, 'outputs', 'cmt'));
    if (!outputsDir.existsSync()) {
      outputsDir.createSync(recursive: true);
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    final inputJsonPath = p.join(outputsDir.path, 'sheet_import_$ts.build.json');
    final outputCmtPath = p.join(outputsDir.path, 'sheet_import_$ts.cmt');

    await File(inputJsonPath).writeAsString(jsonEncode(payload));

    final decoderPath = _resolveDecoderPath();
    final result = await Process.run(
      decoderPath,
      ['--build-cmt', inputJsonPath, outputCmtPath],
      runInShell: false,
    );

    if (result.exitCode != 0) {
      throw StateError('Build .cmt thất bại (exit=${result.exitCode}). ${result.stderr}');
    }

    return {
      'ok': true,
      'spreadsheetId': parsed.spreadsheetId,
      'sheetName': sepSheetName,
      'cmtFilePath': outputCmtPath,
    };
  }

  String _resolveDecoderPath() {
    final candidates = <String>[
      p.join(Directory.current.path, '..', 'decoder', 'bin', 'Release', 'net48', 'decoder.exe'),
      p.join(Directory.current.path, '..', 'decoder', 'bin', 'Debug', 'net48', 'decoder.exe'),
    ];

    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }

    throw StateError('Không tìm thấy decoder.exe. Hãy build apps/decoder trước.');
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
