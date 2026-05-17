import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class AiEvaluationService {
  static const String _defaultBaseUrl = 'http://localhost:11434';
  static const String _defaultModel = 'qwen2.5:7b';

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

  Future<Map<String, dynamic>> evaluateAndRebuildCmt(String cmtJsonPath) async {
    final eval = await evaluateFile(cmtJsonPath);
    final rebuiltPath = await _rebuildCmtFromEvaluatedJson(cmtJsonPath);
    return {
      ...eval,
      'rebuiltCmtPath': rebuiltPath,
    };
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
    final sharedContent = base['content'] as String? ?? '';
    final sharedForm = base['form'] as String? ?? '';
    final sharedAchievement = base['achievement'] as String? ?? '';
    final sharedLimitation = base['limitation'] as String? ?? '';
    final combinedAttitude = base['attitude'] as String? ?? '';

    // ── Data quality guards ──────────────────────────────────────────────
    _validateDataQuality(
      sharedContent: sharedContent,
      sharedForm: sharedForm,
      sharedAchievement: sharedAchievement,
      sharedLimitation: sharedLimitation,
      combinedAttitude: combinedAttitude,
    );
    // ────────────────────────────────────────────────────────────────────

    // malformed output under concurrent load, resulting in fallback decisions for most students.
    final results = <Map<String, dynamic>>[];
    for (final student in students) {
      final roll = student['roll'] as String? ?? '';
      final name = student['name'] as String? ?? '';
      try {
        final evalResult = await _evaluateStudent(
          student,
          sharedContent: sharedContent,
          sharedForm: sharedForm,
          sharedAchievement: sharedAchievement,
          sharedLimitation: sharedLimitation,
          combinedAttitude: combinedAttitude,
        );
        final decision =
            evalResult['decision'] as String? ??
            'revised_for_the_second_defense';
        student['agree_to_defense'] = decision == 'agree_to_defense' ? 'x' : '';
        student['revised_for_the_second_defense'] =
            decision == 'revised_for_the_second_defense' ? 'x' : '';
        student['disagree_to_defend'] = decision == 'disagree_to_defend'
            ? 'x'
            : '';
        student['note'] = evalResult['note'] as String? ?? '';
        results.add({
          'roll': roll,
          'name': name,
          'ok': true,
          'decision': decision,
        });
      } catch (e) {
        results.add({
          'roll': roll,
          'name': name,
          'ok': false,
          'error': e.toString(),
        });
      }
    }

    final successCount = results.where((r) => r['ok'] == true).length;
    final failedCount = results.length - successCount;

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
      roll: roll,
      name: name,
      sharedContent: sharedContent,
      sharedForm: sharedForm,
      sharedAchievement: sharedAchievement,
      sharedLimitation: sharedLimitation,
      combinedAttitude: combinedAttitude,
    );

    // Try up to 2 times — llama3.2 occasionally returns malformed JSON on first attempt
    for (var attempt = 1; attempt <= 2; attempt++) {
      final rawText = await _callOllama(prompt);
      final result = _parseResponse(rawText);
      final isFallback =
          (result['note'] as String?)?.contains('AI không thể xác định') ??
          false;
      if (!isFallback || attempt == 2) return result;
    }
    // Unreachable but satisfies the compiler
    return {
      'decision': 'revised_for_the_second_defense',
      'note': 'AI không thể xác định kết quả rõ ràng. Cần xem xét thủ công.',
    };
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
    final nameParts = name.trim().split(RegExp(r'\s+'));
    final givenName = nameParts.isNotEmpty ? nameParts.last : name;
    final lowerAtitude = combinedAttitude.toLowerCase();
    final nameFound =
        givenName.length > 1 && lowerAtitude.contains(givenName.toLowerCase());

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
2. Dựa vào nhận xét riêng của sinh viên đó VÀ đánh giá chung của nhóm, áp dụng tiêu chí sau:

Tiêu chí quyết định (theo thứ tự ưu tiên):
- "disagree_to_defend": Sinh viên bị đánh giá rất tiêu cực, nhiều lần vi phạm nghiêm trọng, không đủ điều kiện
- "revised_for_the_second_defense": Sinh viên có điểm yếu RÕ RÀNG được nêu tên (chậm trễ, thiếu chủ động, không hoàn thành đúng hạn, vắng họp...) — dù có điểm tích cực đi kèm
- "agree_to_defense": Sinh viên KHÔNG có bất kỳ điểm yếu nào được nêu tên, chỉ có nhận xét tích cực

Lưu ý quan trọng:
- Nếu câu nhận xét về sinh viên vừa có mặt tốt vừa có mặt xấu → chọn "revised_for_the_second_defense"
- Ưu tiên các từ tiêu cực như: "chưa", "chậm", "không", "thiếu", "vắng", "chưa đầy đủ"
- Nếu nội dung không đủ thông tin hoặc không rõ ràng → chọn "revised_for_the_second_defense", không đoán mò

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
    request.write(
      jsonEncode({
        'model': _ollamaModel,
        'prompt': prompt,
        'stream': false,
        'format': 'json',
        'options': {'temperature': 0.1},
      }),
    );

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

  Future<String> _rebuildCmtFromEvaluatedJson(String cmtJsonPath) async {
    final file = File(cmtJsonPath);
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final students = (raw['students'] as List).cast<Map<String, dynamic>>();

    final rows = <List<String>>[
      [
        'Tên khóa luận (Tiếng Việt)',
        'Tên khóa luận (Tiếng Anh)',
        'Roll',
        'Họ tên sinh viên bảo vệ',
        'Nhận xét GV về nội dung khóa luận',
        'Nhận xét GV về hình thức khóa luận',
        'Nhận xét GV về thái độ sinh viên',
        'Kết luận - Mức độ đạt yêu cầu',
        'Kết luận - Hạn chế',
        'AI Decision',
        'AI Note',
      ]
    ];

    for (final s in students) {
      String decisionLabel() {
        if ((s['agree_to_defense'] as String? ?? '').toLowerCase() == 'x') return 'agree_to_defense';
        if ((s['revised_for_the_second_defense'] as String? ?? '').toLowerCase() == 'x') {
          return 'revised_for_the_second_defense';
        }
        if ((s['disagree_to_defend'] as String? ?? '').toLowerCase() == 'x') return 'disagree_to_defend';
        return '';
      }

      rows.add([
        (s['titleVN'] ?? '').toString(),
        (s['titleEN'] ?? '').toString(),
        (s['roll'] ?? '').toString(),
        (s['name'] ?? '').toString(),
        (s['content'] ?? '').toString(),
        (s['form'] ?? '').toString(),
        (s['attitude'] ?? '').toString(),
        (s['achievement'] ?? '').toString(),
        (s['limitation'] ?? '').toString(),
        decisionLabel(),
        (s['note'] ?? '').toString(),
      ]);
    }

    final outDir = p.dirname(cmtJsonPath);
    final stem = p.basename(cmtJsonPath).replaceAll('.cmt.json', '');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final buildJsonPath = p.join(outDir, '${stem}_ai_$ts.build.json');
    final outputCmtPath = p.join(outDir, '${stem}_ai_$ts.cmt');

    await File(buildJsonPath).writeAsString(jsonEncode({
      'spreadsheetId': 'AI_EVAL',
      'sheetName': (raw['sheetName'] ?? 'SEP490_AI').toString(),
      'students': rows,
    }));

    final decoderPath = _resolveDecoderPath();
    final result = await Process.run(decoderPath, ['--build-cmt', buildJsonPath, outputCmtPath], runInShell: false);
    if (result.exitCode != 0) {
      throw StateError('Rebuild .cmt thất bại (exit=${result.exitCode}). ${result.stderr}');
    }
    return outputCmtPath;
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

  Map<String, dynamic> _parseResponse(String rawText) {
    final trimmed = rawText.trim();

    try {
      final parsed = jsonDecode(trimmed) as Map<String, dynamic>;
      final decision = parsed['decision'] as String? ?? '';
      if (_validDecisions.contains(decision)) {
        return {'decision': decision, 'note': parsed['note'] as String? ?? ''};
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
