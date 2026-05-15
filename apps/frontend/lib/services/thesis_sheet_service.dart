import 'dart:io';

import 'package:gsheets/gsheets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/grade_models.dart';

class ThesisSheetService {
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
      'Tên khóa luận (Tiếng Việt)',
      'Tên khóa luận (Tiếng Anh)',
      'Roll',
      'Họ tên sinh viên bảo vệ',
      'Nhận xét GV về nội dung khóa luận',
      'Nhận xét GV về hình thức khóa luận',
      'Nhận xét GV về thái độ sinh viên',
      'Kết luận - Mức độ đạt yêu cầu',
      'Kết luận - Hạn chế',
    ];

    await ws.clear();
    await ws.values.insertRow(1, headers);

    final rows = selectedClass.students.map((s) => <String>[
      '', // Title VN (chưa có trong FG)
      '', // Title EN (chưa có trong FG)
      s.roll,
      s.name,
      _gradeByName(s, 'content_review'),
      _gradeByName(s, 'format_review'),
      _gradeByName(s, 'attitude_review'),
      _extractAchievement(s.comment),
      _extractLimitation(s.comment),
    ]).toList();

    for (var i = 0; i < rows.length; i++) {
      await ws.values.insertRow(i + 2, rows[i]);
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
