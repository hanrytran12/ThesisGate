import 'dart:convert';
import 'dart:io';

import 'package:gsheets/gsheets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis/sheets/v4.dart' as sheets_api;
import 'package:googleapis_auth/auth_io.dart';
import '../models/grade_models.dart';

class ThesisSheetService {
  Future<Map<String, dynamic>> importFromGoogleSheetUrl(
    String sheetUrl, {
    List<String>? sheetNames,
  }) async {
    final baseUrl = dotenv.env['BACKEND_BASE_URL']?.trim().isNotEmpty == true
        ? dotenv.env['BACKEND_BASE_URL']!.trim()
        : 'http://127.0.0.1:8080';

    final res = await http.post(
      Uri.parse('$baseUrl/workflow/sheet/import'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sheetUrl': sheetUrl,
        'strictValidation': true,
        if (sheetNames != null && sheetNames.isNotEmpty) 'sheetNames': sheetNames,
      }),
    );

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400 || body['ok'] != true) {
      final err = (body['error'] as Map<String, dynamic>?)?['message']?.toString() ?? res.body;
      throw Exception(err);
    }

    return body;
  }

  Future<String> createSheetFromClass({
    required SubjectClassResult selectedClass,
    required String semester,
    String? spreadsheetTitle,
  }) async {
    final serviceAccountPath = dotenv.env['GOOGLE_SERVICE_ACCOUNT_PATH']?.trim() ?? '';
    if (serviceAccountPath.isEmpty) {
      throw Exception('Thiếu GOOGLE_SERVICE_ACCOUNT_PATH trong apps/frontend/.env');
    }

    final keyFile = File(serviceAccountPath);
    if (!keyFile.existsSync()) {
      throw Exception('Không tìm thấy file service account JSON tại: $serviceAccountPath');
    }

    final serviceAccountJson = keyFile.readAsStringSync();
    final gsheets = GSheets(serviceAccountJson);

    final spreadsheetId = dotenv.env['GOOGLE_TARGET_SPREADSHEET_ID']?.trim() ?? '';
    if (spreadsheetId.isEmpty) {
      throw Exception('Thiếu GOOGLE_TARGET_SPREADSHEET_ID trong apps/frontend/.env');
    }

    final ss = await gsheets.spreadsheet(spreadsheetId);
    final tabName = '${selectedClass.subject}_${selectedClass.classCode}'.replaceAll(' ', '_');

    final ws = ss.worksheetByTitle(tabName) ?? await ss.addWorksheet(tabName);
    if (ws == null) {
      throw Exception('Không thể tạo worksheet THESIS_EXPORT');
    }

    final headers = <String>[
      'Roll',
      'Họ tên sinh viên bảo vệ',
      'Tên khóa luận (Tiếng Việt)',
      'Tên khóa luận (Tiếng Anh)',
      'Nhận xét GV về nội dung khóa luận',
      'Nhận xét GV về hình thức khóa luận',
      'Nhận xét GV về thái độ sinh viên',
      'Kết luận - Mức độ đạt yêu cầu',
      'Kết luận - Hạn chế',
    ];

    await ws.clear();
    await ws.values.insertRow(1, headers);

    final rows = selectedClass.students.map((s) => <String>[
      s.roll,
      s.name,
      '', // Title VN (chưa có trong FG)
      '', // Title EN (chưa có trong FG)
      _gradeByName(s, 'content_review'),
      _gradeByName(s, 'format_review'),
      _gradeByName(s, 'attitude_review'),
      _extractAchievement(s.comment),
      _extractLimitation(s.comment),
    ]).toList();

    for (var i = 0; i < rows.length; i++) {
      await ws.values.insertRow(i + 2, rows[i]);
    }

    // Tự động Merge Cells cho các cột chung của nhóm
    if (selectedClass.students.length > 1) {
      try {
        final credentials = ServiceAccountCredentials.fromJson(serviceAccountJson);
        final client = await clientViaServiceAccount(credentials, [sheets_api.SheetsApi.spreadsheetsScope]);
        final sheetsApi = sheets_api.SheetsApi(client);

        final borderStyle = sheets_api.Border(style: 'SOLID', color: sheets_api.Color(red: 0.0, green: 0.0, blue: 0.0));
        
        final request = sheets_api.BatchUpdateSpreadsheetRequest(
          requests: [
            // 1. Merge các cột nhận xét
            sheets_api.Request(
              mergeCells: sheets_api.MergeCellsRequest(
                mergeType: 'MERGE_COLUMNS',
                range: sheets_api.GridRange(
                  sheetId: ws.id,
                  startRowIndex: 1,
                  endRowIndex: 1 + selectedClass.students.length,
                  startColumnIndex: 2,
                  endColumnIndex: 9,
                ),
              ),
            ),
            // 2. Format Header (Dòng 1): Nền xanh, chữ trắng, in đậm, căn giữa
            sheets_api.Request(
              repeatCell: sheets_api.RepeatCellRequest(
                range: sheets_api.GridRange(
                  sheetId: ws.id,
                  startRowIndex: 0,
                  endRowIndex: 1,
                  startColumnIndex: 0,
                  endColumnIndex: 9,
                ),
                cell: sheets_api.CellData(
                  userEnteredFormat: sheets_api.CellFormat(
                    backgroundColor: sheets_api.Color(red: 0.2, green: 0.4, blue: 0.8), // Màu xanh dương dương
                    textFormat: sheets_api.TextFormat(
                      bold: true,
                      foregroundColor: sheets_api.Color(red: 1.0, green: 1.0, blue: 1.0), // Chữ trắng
                    ),
                    horizontalAlignment: 'CENTER',
                    verticalAlignment: 'MIDDLE',
                    wrapStrategy: 'WRAP',
                  ),
                ),
                fields: 'userEnteredFormat(backgroundColor,textFormat,horizontalAlignment,verticalAlignment,wrapStrategy)',
              ),
            ),
            // 3. Format Data (Dòng 2 trở đi): Wrap text, căn lên trên cùng
            sheets_api.Request(
              repeatCell: sheets_api.RepeatCellRequest(
                range: sheets_api.GridRange(
                  sheetId: ws.id,
                  startRowIndex: 1,
                  endRowIndex: 1 + selectedClass.students.length,
                  startColumnIndex: 0,
                  endColumnIndex: 9,
                ),
                cell: sheets_api.CellData(
                  userEnteredFormat: sheets_api.CellFormat(
                    verticalAlignment: 'TOP',
                    wrapStrategy: 'WRAP',
                  ),
                ),
                fields: 'userEnteredFormat(verticalAlignment,wrapStrategy)',
              ),
            ),
            // 4. Viền (Borders) cho toàn bộ bảng
            sheets_api.Request(
              updateBorders: sheets_api.UpdateBordersRequest(
                range: sheets_api.GridRange(
                  sheetId: ws.id,
                  startRowIndex: 0,
                  endRowIndex: 1 + selectedClass.students.length,
                  startColumnIndex: 0,
                  endColumnIndex: 9,
                ),
                top: borderStyle,
                bottom: borderStyle,
                left: borderStyle,
                right: borderStyle,
                innerHorizontal: borderStyle,
                innerVertical: borderStyle,
              ),
            ),
            // 5. Chỉnh độ rộng cột cho Roll và Tên
            sheets_api.Request(
              updateDimensionProperties: sheets_api.UpdateDimensionPropertiesRequest(
                range: sheets_api.DimensionRange(
                  sheetId: ws.id,
                  dimension: 'COLUMNS',
                  startIndex: 0,
                  endIndex: 2,
                ),
                properties: sheets_api.DimensionProperties(pixelSize: 150),
                fields: 'pixelSize',
              ),
            ),
            // 6. Chỉnh độ rộng cột cho các cột Nhận xét (Rộng hơn để dễ đọc)
            sheets_api.Request(
              updateDimensionProperties: sheets_api.UpdateDimensionPropertiesRequest(
                range: sheets_api.DimensionRange(
                  sheetId: ws.id,
                  dimension: 'COLUMNS',
                  startIndex: 2,
                  endIndex: 9,
                ),
                properties: sheets_api.DimensionProperties(pixelSize: 300),
                fields: 'pixelSize',
              ),
            ),
          ],
        );

        await sheetsApi.spreadsheets.batchUpdate(request, spreadsheetId);
        client.close();
      } catch (e) {
        print('Không thể merge cells: $e');
      }
    }

    return ss.id;
  }

  String _gradeByName(StudentRecord s, String key) {
    final found = s.grades.where((g) => g.component.trim().toLowerCase() == key).toList();
    if (found.isEmpty) return '';
    return found.first.grade;
  }

  String _extractAchievement(String comment) {
    return comment;
  }

  String _extractLimitation(String comment) {
    return '';
  }
}
