import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AiEvaluationService {
  static const String _defaultBaseUrl = 'http://localhost:11434';
  static const String _defaultModel = 'llama3.2';

  // Minimum characters the longest single evaluation field must have.
  // Blocks completely empty files and obvious placeholder/test data.
  static const int _minFieldLength = 10;

  static const Set<String> _validDecisions = {
    'agree_to_defense',
    'revised_for_the_second_defense',
    'disagree_to_defend',
  };

  // Cached at construction — avoids re-reading .env on every Ollama call
  final String _ollamaBaseUrl;
  final String _ollamaModel;

  AiEvaluationService()
      : _ollamaBaseUrl = _readEnvKey('OLLAMA_BASE_URL') ?? _defaultBaseUrl,
        _ollamaModel = _readEnvKey('OLLAMA_MODEL') ?? _defaultModel;

  static String? _readEnvKey(String key) {
    final fromOs = Platform.environment[key];
    if (fromOs != null && fromOs.trim().isNotEmpty) return fromOs.trim();

    final envFile = File('.env');
    if (!envFile.existsSync()) return null;

    for (final raw in envFile.readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (!line.startsWith('$key=')) continue;
      var value = line.substring('$key='.length).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  Future<Map<String, dynamic>> evaluateFile(String cmtJsonPath) async {
    final file = File(cmtJsonPath);
    if (!await file.exists()) {
      throw StateError('Không tìm thấy file .cmt.json: $cmtJsonPath');
    }

    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (raw['format'] != 'ThesisGate-CMT-v1') {
      throw StateError('Định dạng file không hợp lệ (cần ThesisGate-CMT-v1).');
    }

    final students = (raw['students'] as List).cast<Map<String, dynamic>>();
    if (students.isEmpty) {
      throw StateError('File không có sinh viên nào để đánh giá.');
    }

    // Extract shared thesis-level context from the first student with non-empty content.
    // Google Sheets merged cells only populate the first row; subsequent rows are empty.
    final base = students.firstWhere(
      (s) => (s['content'] as String? ?? '').isNotEmpty,
      orElse: () => students.first,
    );
    final sharedContent     = base['content']     as String? ?? '';
    final sharedForm        = base['form']        as String? ?? '';
    final sharedAchievement = base['achievement'] as String? ?? '';
    final sharedLimitation  = base['limitation']  as String? ?? '';
    final combinedAttitude  = base['attitude']    as String? ?? '';

    // ── Data quality guards ──────────────────────────────────────────────
    _validateDataQuality(
      sharedContent:     sharedContent,
      sharedForm:        sharedForm,
      sharedAchievement: sharedAchievement,
      sharedLimitation:  sharedLimitation,
      combinedAttitude:  combinedAttitude,
    );
    // ────────────────────────────────────────────────────────────────────

    // Evaluate all students in parallel — Ollama queues internally, no shared state per student
    final evalFutures = students.map((student) async {
      final roll = student['roll'] as String? ?? '';
      try {
        final evalResult = await _evaluateStudent(
          student,
          sharedContent:     sharedContent,
          sharedForm:        sharedForm,
          sharedAchievement: sharedAchievement,
          sharedLimitation:  sharedLimitation,
          combinedAttitude:  combinedAttitude,
        );
        final decision = evalResult['decision'] as String? ?? 'revised_for_the_second_defense';
        student['agree_to_defense']               = decision == 'agree_to_defense'               ? 'x' : '';
        student['revised_for_the_second_defense'] = decision == 'revised_for_the_second_defense' ? 'x' : '';
        student['disagree_to_defend']             = decision == 'disagree_to_defend'             ? 'x' : '';
        student['note']                           = evalResult['note'] as String? ?? '';
        return <String, dynamic>{'roll': roll, 'ok': true, 'decision': decision};
      } catch (e) {
        return <String, dynamic>{'roll': roll, 'ok': false, 'error': e.toString()};
      }
    });

    final results = await Future.wait(evalFutures);
    final successCount = results.where((r) => r['ok'] == true).length;
    final failedCount  = results.length - successCount;

    raw['evaluatedAt'] = DateTime.now().toIso8601String();
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(raw));

    return {
      'ok': failedCount == 0,
      'cmtJsonPath': cmtJsonPath,
      'successCount': successCount,
      'failedCount': failedCount,
      'results': results,
    };
  }

  // Throws a descriptive StateError if the evaluation data is clearly unusable.
  void _validateDataQuality({
    required String sharedContent,
    required String sharedForm,
    required String sharedAchievement,
    required String sharedLimitation,
    required String combinedAttitude,
  }) {
    final fields = [
      sharedContent,
      sharedForm,
      sharedAchievement,
      sharedLimitation,
      combinedAttitude,
    ];

    // Find the length of the longest non-empty trimmed field.
    final longestField = fields.fold<int>(
      0,
      (acc, f) => f.trim().length > acc ? f.trim().length : acc,
    );

    if (longestField == 0) {
      throw StateError(
        'Không thể đánh giá: tất cả các trường nhận xét trong file đều trống '
        '(content, form, achievement, limitation, attitude). '
        'Kiểm tra Google Sheet đã được điền đầy đủ và thực hiện import lại.',
      );
    }

    if (longestField < _minFieldLength) {
      throw StateError(
        'Không thể đánh giá: nội dung nhận xét quá ngắn '
        '(trường dài nhất chỉ có $longestField ký tự, '
        'cần ít nhất $_minFieldLength ký tự). '
        'File có thể chứa dữ liệu thử nghiệm — kiểm tra lại Google Sheet.',
      );
    }
  }

  Future<Map<String, dynamic>> _evaluateStudent(
    Map<String, dynamic> student, {
    required String sharedContent,
    required String sharedForm,
    required String sharedAchievement,
    required String sharedLimitation,
    required String combinedAttitude,
  }) async {
    final name = student['name'] as String? ?? '';
    final roll = student['roll'] as String? ?? '';

    if (name.isEmpty && roll.isEmpty) {
      throw StateError('Sinh viên không có tên và mã số, bỏ qua đánh giá.');
    }

    final prompt = _buildPrompt(
      roll:              roll,
      name:              name,
      sharedContent:     sharedContent,
      sharedForm:        sharedForm,
      sharedAchievement: sharedAchievement,
      sharedLimitation:  sharedLimitation,
      combinedAttitude:  combinedAttitude,
    );
    final rawText = await _callOllama(prompt);
    return _parseResponse(rawText);
  }

  String _buildPrompt({
    required String roll,
    required String name,
    required String sharedContent,
    required String sharedForm,
    required String sharedAchievement,
    required String sharedLimitation,
    required String combinedAttitude,
  }) {
    // Check whether the student's name can be found in the attitude paragraph.
    // Use the given name (last Vietnamese name component) as it is the most distinctive.
    final nameParts  = name.trim().split(RegExp(r'\s+'));
    final givenName  = nameParts.isNotEmpty ? nameParts.last : name;
    final lowerAtitude = combinedAttitude.toLowerCase();
    final nameFound  = givenName.length > 1 &&
        lowerAtitude.contains(givenName.toLowerCase());

    final attitudeBlock = combinedAttitude.trim().isNotEmpty
        ? combinedAttitude
        : '(Không có nhận xét thái độ riêng cho nhóm này — chỉ dựa vào đánh giá chung để quyết định)';

    final nameHint = (!nameFound && combinedAttitude.trim().isNotEmpty)
        ? '\nLưu ý: Không tìm thấy tên "$name" trong đoạn nhận xét thái độ. '
          'Chỉ dựa vào đánh giá chung của nhóm để quyết định.'
        : '';

    return '''Bạn là hội đồng phản biện khóa luận tốt nghiệp đại học.

ĐÁNH GIÁ CHUNG CỦA NHÓM (áp dụng cho tất cả sinh viên trong nhóm):
- Nhận xét nội dung: $sharedContent
- Nhận xét hình thức: $sharedForm
- Mức độ đạt yêu cầu: $sharedAchievement
- Hạn chế: $sharedLimitation

NHẬN XÉT THÁI ĐỘ TỪNG SINH VIÊN (đoạn văn chứa đánh giá riêng của từng người):
$attitudeBlock

SINH VIÊN CẦN ĐÁNH GIÁ: $name ($roll)$nameHint

Nhiệm vụ:
1. Tìm câu/đoạn trong phần "NHẬN XÉT THÁI ĐỘ" đề cập đến sinh viên "$name"
2. Dựa vào nhận xét riêng của sinh viên đó VÀ đánh giá chung của nhóm, quyết định:
   - "agree_to_defense": Đồng ý cho sinh viên bảo vệ khóa luận
   - "revised_for_the_second_defense": Yêu cầu chỉnh sửa và bảo vệ lần 2
   - "disagree_to_defend": Không đồng ý cho bảo vệ

QUAN TRỌNG: Nếu nội dung nhận xét không đủ thông tin, không rõ ràng hoặc không có ý nghĩa thực tế để đưa ra quyết định có căn cứ, hãy trả về "revised_for_the_second_defense" với note giải thích — không được đoán mò.

Trả lời CHÍNH XÁC theo định dạng JSON, không thêm bất kỳ text nào khác:
{"decision": "<một trong ba giá trị trên>", "note": "<lý do ngắn gọn tối đa 2 câu bằng tiếng Việt>"}''';
  }

  Future<String> _callOllama(String prompt) async {
    final uri = Uri.parse('$_ollamaBaseUrl/api/generate');

    // connectionTimeout covers "Ollama not running" fast-fail (10 s).
    // The outer Future.timeout covers slow inference / cold model load (10 min).
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      return await _doRequest(client, uri, prompt).timeout(
        const Duration(minutes: 10),
        onTimeout: () => throw TimeoutException(
          'Ollama không phản hồi trong 10 phút. '
          'Model "$_ollamaModel" có thể đang tải hoặc máy quá chậm.',
        ),
      );
    } on SocketException catch (e) {
      throw StateError(
        'Không kết nối được Ollama tại $_ollamaBaseUrl. '
        'Kiểm tra Ollama đang chạy (ollama serve). Chi tiết: ${e.message}',
      );
    } on TimeoutException {
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<String> _doRequest(HttpClient client, Uri uri, String prompt) async {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'model': _ollamaModel,
      'prompt': prompt,
      'stream': false,
      'format': 'json',
      'options': {'temperature': 0.1},
    }));

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode == 404) {
      throw StateError(
        'Model "$_ollamaModel" không tồn tại trong Ollama. '
        'Chạy lệnh: ollama pull $_ollamaModel',
      );
    }

    if (response.statusCode != 200) {
      Map<String, dynamic>? errMap;
      try {
        errMap = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {}
      final msg = errMap?['error'] as String? ?? body;
      throw StateError('Ollama trả về lỗi HTTP ${response.statusCode}: $msg');
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    return decoded['response'] as String? ?? '';
  }

  Map<String, dynamic> _parseResponse(String rawText) {
    final trimmed = rawText.trim();

    try {
      final parsed = jsonDecode(trimmed) as Map<String, dynamic>;
      final decision = parsed['decision'] as String? ?? '';
      if (_validDecisions.contains(decision)) {
        return {
          'decision': decision,
          'note': parsed['note'] as String? ?? '',
        };
      }
    } catch (_) {
      // JSON parse failed — fall through to substring fallback
    }

    // Substring fallback for malformed responses
    if (trimmed.contains('agree_to_defense') && !trimmed.contains('disagree')) {
      return {'decision': 'agree_to_defense', 'note': ''};
    }
    if (trimmed.contains('revised_for_the_second_defense')) {
      return {'decision': 'revised_for_the_second_defense', 'note': ''};
    }

    return {
      'decision': 'revised_for_the_second_defense',
      'note': 'AI không thể xác định kết quả rõ ràng. Cần xem xét thủ công.',
    };
  }
}
