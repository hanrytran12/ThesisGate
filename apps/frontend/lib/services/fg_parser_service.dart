// ============================================================
// fg_parser_service.dart — Phase 3: Dart ↔ C# IPC
// Dùng dart:io Process.run() để gọi decoder.exe
// và parse JSON output thành Dart models
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../models/grade_models.dart';

class FgParserService {
  // Timeout cho decoder.exe (tránh treo vô hạn)
  static const _timeout = Duration(seconds: 15);

  // ──────────────────────────────────────────────────────────
  // Tìm đường dẫn decoder.exe theo thứ tự ưu tiên:
  //   1. Cùng thư mục với frontend.exe (production)
  //   2. Thư mục build Debug trong monorepo (dev mode)
  //   3. Thư mục build Release trong monorepo (dev mode)
  // ──────────────────────────────────────────────────────────
  static String? _findDecoderPath() {
    final exeDir = p.dirname(Platform.resolvedExecutable);

    final candidates = [
      // 1. Production: decoder.exe cạnh frontend.exe
      p.join(exeDir, 'decoder.exe'),

      // 2. Dev: Chạy từ 'apps/frontend' (flutter run)
      p.join(Directory.current.path, '..', 'decoder', 'bin', 'Debug', 'net48', 'decoder.exe'),
      p.join(Directory.current.path, '..', 'decoder', 'bin', 'Release', 'publish', 'decoder.exe'),

      // 3. Dev: Chạy từ thư mục gốc của project (melos run)
      p.join(Directory.current.path, 'apps', 'decoder', 'bin', 'Debug', 'net48', 'decoder.exe'),
      p.join(Directory.current.path, 'apps', 'decoder', 'bin', 'Release', 'publish', 'decoder.exe'),
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  // ──────────────────────────────────────────────────────────
  // PUBLIC: Mở FilePicker → gọi decoder.exe → trả FgOutput
  // ──────────────────────────────────────────────────────────
  Future<FgParserResult> parseFile() async {
    // BƯỚC 1: Chọn file .fg
    final pickerResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['fg'],
      allowMultiple: false,
      dialogTitle: 'Chọn file chấm điểm (.fg)',
    );

    if (pickerResult == null || pickerResult.files.isEmpty) {
      return FgParserResult.cancelled();
    }

    final filePath = pickerResult.files.single.path;
    if (filePath == null) {
      return FgParserResult.error('Không thể lấy đường dẫn file.');
    }

    // BƯỚC 2: Tìm decoder.exe
    final decoderPath = _findDecoderPath();
    if (decoderPath == null) {
      return FgParserResult.error(
        'Không tìm thấy decoder.exe.\n'
        'Hãy đảm bảo đã build C# project:\n'
        '  cd apps/decoder && dotnet build',
      );
    }

    // BƯỚC 3: Gọi decoder.exe qua Process.run()
    return _runDecoder(decoderPath, filePath);
  }

  // ──────────────────────────────────────────────────────────
  // PRIVATE: Thực thi decoder.exe và parse kết quả
  // ──────────────────────────────────────────────────────────
  Future<FgParserResult> _runDecoder(
      String decoderPath, String filePath) async {
    ProcessResult processResult;

    try {
      // Chạy decoder.exe với timeout để tránh treo
      processResult = await Process.run(
        decoderPath,
        [filePath],
        stdoutEncoding: systemEncoding,
        stderrEncoding: systemEncoding,
      ).timeout(
        _timeout,
        onTimeout: () => throw TimeoutException(
          'decoder.exe không phản hồi sau ${_timeout.inSeconds}s',
        ),
      );
    } on TimeoutException catch (e) {
      return FgParserResult.error('Timeout: ${e.message}');
    } on ProcessException catch (e) {
      return FgParserResult.error(
          'Không thể chạy decoder.exe:\n${e.message}');
    } catch (e) {
      return FgParserResult.error('Lỗi không xác định: $e');
    }

    // BƯỚC 4: Kiểm tra exit code
    if (processResult.exitCode != 0) {
      final stderr = (processResult.stderr as String).trim();
      return FgParserResult.error(
        'decoder.exe thất bại (exit ${processResult.exitCode})'
        '${stderr.isNotEmpty ? ":\n$stderr" : ""}',
      );
    }

    // BƯỚC 5: Parse JSON stdout → Dart models
    final stdout = (processResult.stdout as String).trim();
    if (stdout.isEmpty) {
      return FgParserResult.error(
          'decoder.exe không trả về dữ liệu (stdout rỗng).');
    }

    try {
      final jsonMap = jsonDecode(stdout) as Map<String, dynamic>;
      final fgOutput = FgOutput.fromJson(jsonMap);

      // LỌC: Chỉ giữ lại các lớp thuộc môn đồ án SEP490
      fgOutput.subjectClasses.retainWhere((sc) => sc.subject.trim().toUpperCase() == 'SEP490');

      // Validate có dữ liệu thực sự
      if (fgOutput.subjectClasses.isEmpty) {
        return FgParserResult.error(
          'File .fg đọc thành công nhưng KHÔNG tìm thấy lớp đồ án (SEP490) nào.\n'
          'Vui lòng chọn đúng file của kỳ bảo vệ.',
        );
      }

      return FgParserResult.success(fgOutput, p.basename(filePath));
    } on FormatException catch (e) {
      return FgParserResult.error(
        'JSON không hợp lệ từ decoder.exe:\n${e.message}\n\n'
        'Stdout (100 chars đầu):\n${stdout.substring(0, stdout.length.clamp(0, 100))}',
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════
// Result wrapper — rõ ràng, type-safe
// ═══════════════════════════════════════════════════════════
class FgParserResult {
  final FgOutput? data;
  final String? fileName;
  final String? errorMessage;
  final bool cancelled;

  const FgParserResult._({
    this.data,
    this.fileName,
    this.errorMessage,
    this.cancelled = false,
  });

  factory FgParserResult.success(FgOutput data, String fileName) =>
      FgParserResult._(data: data, fileName: fileName);

  factory FgParserResult.error(String message) =>
      FgParserResult._(errorMessage: message);

  factory FgParserResult.cancelled() =>
      FgParserResult._(cancelled: true);

  bool get isSuccess => data != null;
  bool get hasError  => errorMessage != null;
}
