// ============================================================
// home_screen.dart — Màn hình chính của ThesisGate
// Tính năng:
//   • Import file .fg → gọi decoder.exe → hiển thị DataTable
//   • Dropdown chọn lớp (SubjectClass)
//   • Hiển thị danh sách sinh viên với grades
//   • Nút Export (Phase 4 & 5)
// ============================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/grade_models.dart';
import '../services/fg_parser_service.dart';
import '../services/thesis_sheet_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ── State ──────────────────────────────────────────────────
  final _parserService = FgParserService();
  final _sheetService = ThesisSheetService();

  FgOutput?           _fgData;
  SubjectClassResult? _selectedClass;
  String?             _fileName;
  String?             _filePath;
  bool                _isLoading = false;
  String?             _errorMessage;
  bool                _isCreatingSheet = false;
  bool                _isImportingSheet = false;
  String?             _lastSheetError;
  String?             _lastSheetUrl;
  bool                _isEvaluating = false;
  final List<String>  _cmtJsonPaths = [];
  final TextEditingController _sheetUrlController = TextEditingController();
  final ScrollController _infoHorizontalController = ScrollController();
  final ScrollController _reviewHorizontalController = ScrollController();
  final Map<String, Map<String, String>> _manualInfoByRoll = {};

  @override
  void dispose() {
    _sheetUrlController.dispose();
    _infoHorizontalController.dispose();
    _reviewHorizontalController.dispose();
    super.dispose();
  }

  String _manualInfo(String roll, String key, String original) {
    return _manualInfoByRoll[roll]?[key] ?? original;
  }

  Future<void> _editInfoForStudent(StudentRecord stu, {String comment = '', String agree = '', String revised = '', String disagree = '', String note = ''}) async {
    final saved = _manualInfoByRoll[stu.roll] ?? {};
    final cComment = TextEditingController(text: _manualInfo(stu.roll, 'comment', comment));
    final cAgree = TextEditingController(text: _manualInfo(stu.roll, 'agree', agree));
    final cRevised = TextEditingController(text: _manualInfo(stu.roll, 'revised', revised));
    final cDisagree = TextEditingController(text: _manualInfo(stu.roll, 'disagree', disagree));
    final cNote = TextEditingController(text: _manualInfo(stu.roll, 'note', note));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Text('Edit: ${stu.roll}', style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: cComment, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Comment')),
            TextField(controller: cAgree, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Agree_to_defense')),
            TextField(controller: cRevised, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Revised_for_the_second_defennse')),
            TextField(controller: cDisagree, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Disagree_to_defense')),
            TextField(controller: cNote, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Note')),
          ]),
        ),
        actions: [TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Hủy')), FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('Lưu'))],
      ),
    );

    if (ok == true) {
      setState(() {
        _manualInfoByRoll[stu.roll] = {
          ...saved,
          'comment': cComment.text.trim(),
          'agree': cAgree.text.trim(),
          'revised': cRevised.text.trim(),
          'disagree': cDisagree.text.trim(),
          'note': cNote.text.trim(),
        };
      });
    }
  }

  // Columns hiển thị — luôn có STT, Roll, Name, Comment + các Grade components
  List<String> get _gradeComponents {
    if (_selectedClass == null || _selectedClass!.students.isEmpty) return [];
    return _selectedClass!.students.first.grades
        .map((g) => g.component)
        .toList();
  }

  // ── Actions ────────────────────────────────────────────────

  Future<void> _importFile() async {
    setState(() {
      _isLoading    = true;
      _errorMessage = null;
    });

    final result = await _parserService.parseFile();

    if (result.cancelled) {
      setState(() => _isLoading = false);
      return;
    }

    if (result.hasError) {
      setState(() {
        _isLoading    = false;
        _errorMessage = result.errorMessage;
      });
      return;
    }

    setState(() {
      _fgData        = result.data;
      _fileName      = result.fileName;
      _selectedClass = result.data!.subjectClasses.isNotEmpty
          ? result.data!.subjectClasses.first
          : null;
      _filePath      = result.filePath;
      _isLoading    = false;
    });
  }

  void _onClassChanged(SubjectClassResult? value) {
    setState(() => _selectedClass = value);
  }

  Future<void> _saveCommentToFg() async {
    if (_selectedClass == null || _filePath == null) return;

    final comments = <String, String>{};
    for (final stu in _selectedClass!.students) {
      comments[stu.roll] = _manualInfo(stu.roll, 'comment', stu.comment).trim();
    }

    setState(() => _isLoading = true);
    final result = await _parserService.saveCommentsToFg(
      fgPath: _filePath!,
      commentsByRoll: comments,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: const Color(0xFFDA3633), content: Text(result.errorMessage ?? 'Save thất bại')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF238636),
        content: Text('Save Comment to .FG xong: ${result.updated} thành công, ${result.failed} thất bại. Backup: ${result.backupPath}'),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _clearData() {
    setState(() {
      _fgData        = null;
      _selectedClass = null;
      _fileName      = null;
      _filePath      = null;
      _errorMessage  = null;
      _cmtJsonPaths.clear();
    });
  }

  Future<void> _showImportSheetDialog() async {
    final selectedTabs = <String>{};
    List<String> tabs = [];
    String? error;
    bool loadingTabs = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Text('Import Google Sheet', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _sheetUrlController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Dán link Google Sheet...',
                    hintStyle: TextStyle(color: Color(0xFF8B949E)),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: loadingTabs
                          ? null
                          : () async {
                              final url = _sheetUrlController.text.trim();
                              if (url.isEmpty) return;
                              setLocal(() {
                                loadingTabs = true;
                                error = null;
                                tabs = [];
                                selectedTabs.clear();
                              });
                              try {
                                final found = await _sheetService.listImportTabs(url);
                                setLocal(() {
                                  tabs = found;
                                  selectedTabs.addAll(found);
                                });
                              } catch (e) {
                                final raw = e.toString();
                                final cleaned = raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
                                final invalidUrl = cleaned.contains('URL Google Sheet không hợp lệ');
                                setLocal(() => error = invalidUrl
                                    ? 'URL Google Sheet không hợp lệ.'
                                    : (cleaned.isEmpty ? 'URL Google Sheet không hợp lệ.' : cleaned));
                              } finally {
                                setLocal(() => loadingTabs = false);
                              }
                            },
                      child: Text(loadingTabs ? 'Đang tải tab...' : 'Kiểm tra tab'),
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Color(0xFFDA3633))),
                ],
                if (tabs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('Chọn tab lấy dữ liệu:', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: Column(
                        children: tabs
                            .map(
                              (t) => CheckboxListTile(
                                value: selectedTabs.contains(t),
                                onChanged: (v) {
                                  setLocal(() {
                                    if (v == true) {
                                      selectedTabs.add(t);
                                    } else {
                                      selectedTabs.remove(t);
                                    }
                                  });
                                },
                                title: Text(t, style: const TextStyle(color: Colors.white)),
                                controlAffinity: ListTileControlAffinity.trailing,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Huỷ')),
            TextButton(
              onPressed: _isImportingSheet || selectedTabs.isEmpty
                  ? null
                  : () async {
                      final url = _sheetUrlController.text.trim();
                      final selected = selectedTabs.toList();
                      Navigator.of(ctx).pop();
                      await _importSheetToCmt(url, selected);
                    },
              child: const Text('Lây dữ liệu'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importSheetToCmt(String sheetUrl, List<String> selectedTabs) async {
    setState(() => _isImportingSheet = true);
    try {
      final result = await _sheetService.importFromGoogleSheetUrl(sheetUrl, sheetNames: selectedTabs);
      if (!mounted) return;

      // Tích lũy cmtJsonPath từ các tab thành công
      final results = (result['results'] as List?) ?? [];
      final typedResults = results.whereType<Map<String, dynamic>>().toList();
      final newPaths = typedResults
          .where((r) => r['ok'] == true)
          .map((r) => r['cmtJsonPath'] as String?)
          .whereType<String>()
          .toList();
      if (newPaths.isNotEmpty) {
        setState(() {
          for (final path in newPaths) {
            if (!_cmtJsonPaths.contains(path)) _cmtJsonPaths.add(path);
          }
        });
      }

      // Luôn hiển thị dialog kết quả (kể cả chọn 1 tab và lỗi)
      await _showImportResultDialog(typedResults);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDA3633),
          content: Text('Import sheet thất bại: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _isImportingSheet = false);
    }
  }

  Future<void> _showImportResultDialog(List<Map<String, dynamic>> results) async {
    final successItems = results.where((r) => r['ok'] == true).toList();
    final failedItems  = results.where((r) => r['ok'] != true).toList();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: failedItems.isNotEmpty && successItems.isEmpty
                ? const Color(0xFFDA3633)
                : failedItems.isNotEmpty
                    ? const Color(0xFFD29922)
                    : const Color(0xFF238636),
            width: 1,
          ),
        ),
        title: Row(
          children: [
            Icon(
              failedItems.isNotEmpty && successItems.isEmpty
                  ? Icons.error_outline
                  : failedItems.isNotEmpty
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
              color: failedItems.isNotEmpty && successItems.isEmpty
                  ? const Color(0xFFDA3633)
                  : failedItems.isNotEmpty
                      ? const Color(0xFFD29922)
                      : const Color(0xFF3FB950),
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Kết quả lấy dữ liệu (${successItems.length} thành công / ${failedItems.length} lỗi)',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kết quả từng tab:',
                style: TextStyle(color: Color(0xFF8B949E), fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 360),
                child: SingleChildScrollView(
                  child: Column(
                    children: results.map((item) {
                      final ok = item['ok'] == true;
                      return ok
                          ? _ImportResultSuccessRow(item: item)
                          : _ImportResultWarningRow(item: item);
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Đóng', style: TextStyle(color: Color(0xFF8B949E))),
          ),
        ],
      ),
    );
  }

  List<String> _scanExistingCmtJsonPaths() {
    final candidates = <Directory>[
      Directory('${Directory.current.path}${Platform.pathSeparator}outputs${Platform.pathSeparator}cmt'),
      Directory('${Directory.current.path}${Platform.pathSeparator}..${Platform.pathSeparator}backend${Platform.pathSeparator}outputs${Platform.pathSeparator}cmt'),
      Directory('${Directory.current.path}${Platform.pathSeparator}apps${Platform.pathSeparator}backend${Platform.pathSeparator}outputs${Platform.pathSeparator}cmt'),
    ];

    final found = <String>{};
    for (final dir in candidates) {
      if (!dir.existsSync()) continue;
      for (final e in dir.listSync(recursive: false, followLinks: false)) {
        if (e is! File) continue;
        final p = e.path.toLowerCase();
        if (p.endsWith('.cmt.json')) {
          found.add(e.path);
        }
      }
    }

    final paths = found.toList()
      ..sort((a, b) => File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync()));
    return paths;
  }


  Future<void> _evaluateWithAi() async {
    final existingPaths = _scanExistingCmtJsonPaths();

    setState(() {
      _cmtJsonPaths
        ..clear()
        ..addAll(existingPaths);
    });

    if (existingPaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFDA3633),
          content: Text('Không tìm thấy file .cmt.json nào trong outputs/cmt'),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    String? pathToEvaluate;
    if (existingPaths.length == 1) {
      pathToEvaluate = existingPaths.first;
    } else {
      pathToEvaluate = await _showCmtPickerDialog();
      if (pathToEvaluate == null) return;
    }

    final fileName = pathToEvaluate.replaceAll('\\', '/').split('/').last;
    final elapsed = ValueNotifier<int>(0);
    final timer = Timer.periodic(const Duration(seconds: 1), (_) => elapsed.value++);

    setState(() => _isEvaluating = true);

    // Show non-dismissible progress dialog with live elapsed timer
    if (!mounted) return;
    // ignore: unawaited_futures
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EvaluatingDialog(fileName: fileName, elapsed: elapsed),
    );

    try {
      final result = await _sheetService.evaluateCmtWithAi(pathToEvaluate);
      if (!mounted) return;
      Navigator.of(context).pop(); // close progress dialog
      await _showAiEvalResultDialog(result);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // close progress dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDA3633),
          content: Text('Đánh giá AI thất bại: $e'),
          duration: const Duration(seconds: 10),
        ),
      );
    } finally {
      timer.cancel();
      elapsed.dispose();
      if (mounted) setState(() => _isEvaluating = false);
    }
  }

  Future<String?> _showCmtPickerDialog() async {
    String? selected;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF6E40C9), width: 1),
        ),
        title: Row(children: [
          const Icon(Icons.psychology_outlined, color: Color(0xFF8957E5), size: 22),
          const SizedBox(width: 10),
          const Text(
            'Chọn file dữ liệu để đánh giá',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ]),
        content: SizedBox(
          width: 580,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Có ${_cmtJsonPaths.length} file .cmt.json đã được tạo. Chọn file cần đánh giá:',
                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: Column(
                    children: _cmtJsonPaths.map((path) {
                      final displayName = path.replaceAll('\\', '/').split('/').last;
                      return InkWell(
                        onTap: () {
                          selected = path;
                          Navigator.of(ctx).pop();
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D1117),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF30363D)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.description_outlined,
                                  color: Color(0xFF8957E5), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      path,
                                      style: const TextStyle(
                                          color: Color(0xFF8B949E), fontSize: 11, fontFamily: 'monospace'),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Color(0xFF8B949E), size: 18),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Huỷ', style: TextStyle(color: Color(0xFF8B949E))),
          ),
        ],
      ),
    );
    return selected;
  }

  Future<void> _showAiEvalResultDialog(Map<String, dynamic> result) async {
    final items = ((result['results'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF8957E5), width: 1),
        ),
        title: Row(children: [
          const Icon(Icons.psychology_outlined, color: Color(0xFF8957E5), size: 22),
          const SizedBox(width: 10),
          Text(
            'Kết quả đánh giá AI (${items.length} sinh viên)',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ]),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Thành công: ${result['successCount']}  |  Lỗi: ${result['failedCount']}',
                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
              ),
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 360),
                child: SingleChildScrollView(
                  child: Column(
                    children: items.map((item) => _AiResultRow(item: item)).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Đóng', style: TextStyle(color: Color(0xFF8B949E))),
          ),
        ],
      ),
    );
  }

  Future<void> _createThesisSheet() async {
    if (_selectedClass == null || _fgData == null) return;

    setState(() => _isCreatingSheet = true);

    try {
      final spreadsheetId = await _sheetService.createSheetFromClass(
        selectedClass: _selectedClass!,
        semester: _fgData!.semester,
      );

      if (!mounted) return;
      final sheetUrl = 'https://docs.google.com/spreadsheets/d/$spreadsheetId';
      setState(() {
        _lastSheetError = null;
        _lastSheetUrl = sheetUrl;
      });
      await _showSheetSuccessDialog(sheetUrl);
    } catch (e) {
      if (!mounted) return;
      final msg = 'Tạo Google Sheet thất bại: $e';
      setState(() => _lastSheetError = msg);
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Text('Lỗi tạo Google Sheet', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: SelectableText(msg, style: const TextStyle(color: Color(0xFFE6EDF3))),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đóng'),
            )
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isCreatingSheet = false);
      }
    }
  }

  Future<void> _showSheetSuccessDialog(String sheetUrl) async {
    bool copied = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF238636), width: 1),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF238636).withAlpha(40),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline,
                    color: Color(0xFF3FB950), size: 22),
              ),
              const SizedBox(width: 12),
              const Text(
                'Google Sheet đã tạo xong!',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dán link này vào Google Sheets:',
                  style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
                ),
                const SizedBox(height: 10),
                // Link box
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link,
                          size: 16, color: Color(0xFF2188FF)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SelectableText(
                          sheetUrl,
                          style: const TextStyle(
                            color: Color(0xFF79C0FF),
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Copy button (full width)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: sheetUrl));
                      setLocal(() => copied = true);
                    },
                    icon: Icon(
                      copied
                          ? Icons.check_rounded
                          : Icons.copy_rounded,
                      size: 16,
                    ),
                    label: Text(copied ? 'Đã copy!' : 'Copy link'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: copied
                          ? const Color(0xFF238636)
                          : const Color(0xFF21262D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Đóng',
                  style: TextStyle(color: Color(0xFF8B949E))),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(sheetUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri,
                      mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_browser, size: 16),
              label: const Text('Mở trong trình duyệt'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F6FEB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Column(
        children: [
          _buildTopBar(),
          if (_errorMessage != null) _buildErrorBanner(),
          if (_lastSheetError != null) _buildSheetErrorBanner(),
          if (_fgData != null) ...[
            _buildInfoBar(),
            _buildClassSelector(),
            const Divider(color: Color(0xFF21262D), height: 1),
            Expanded(child: _buildClassTabs()),
          ] else if (!_isLoading)
            Expanded(child: _buildEmptyState()),
          if (_isLoading)
            const Expanded(child: Center(child: _LoadingWidget())),
        ],
      ),
    );
  }

  // ── Top App Bar ────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      height: 56,
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6E40C9), Color(0xFF2188FF)],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'ThesisGate',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Tên file đang mở
          if (_fileName != null)
            Expanded(
              child: Row(
                children: [
                  const Icon(Icons.folder_open,
                      size: 14, color: Color(0xFF8B949E)),
                  const SizedBox(width: 6),
                  Text(
                    _fileName!,
                    style: const TextStyle(
                        color: Color(0xFF8B949E), fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            )
          else
            const Spacer(),

          // Nút Import
          _TopBarButton(
            icon: Icons.upload_file_outlined,
            label: 'Import .FG',
            color: const Color(0xFF238636),
            onPressed: _isLoading ? null : _importFile,
          ),

          if (_fgData != null) ...[

            const SizedBox(width: 8),
            _TopBarButton(
              icon: Icons.cloud_download_outlined,
              label: _isImportingSheet ? 'Đang import link...' : 'Import link',
              color: const Color(0xFF8957E5),
              onPressed: _isImportingSheet ? null : _showImportSheetDialog,
            ),
            const SizedBox(width: 8),
            _TopBarButton(
              icon: Icons.psychology_outlined,
              label: _isEvaluating ? 'Đang đánh giá...' : 'Đánh giá với AI',
              color: const Color(0xFF6E40C9),
              onPressed: _isEvaluating ? null : _evaluateWithAi,
            ),
            const SizedBox(width: 8),
            _TopBarButton(
              icon: Icons.save_outlined,
              label: _isLoading ? 'Đang lưu...' : 'Save Changes',
              color: const Color(0xFF1F6FEB),
              onPressed: _isLoading ? null : _saveCommentToFg,
            ),
            const SizedBox(width: 8),

            // Nút Clear
            IconButton(
              onPressed: _clearData,
              icon: const Icon(Icons.close, size: 18),
              color: const Color(0xFF8B949E),
              tooltip: 'Đóng file',
            ),
          ],
        ],
      ),
    );
  }

  // ── Info Bar (semester, login, tổng lớp) ──────────────────

  Widget _buildInfoBar() {
    final data = _fgData!;
    return Container(
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          _InfoChip(
              icon: Icons.school_outlined,
              label: 'Semester',
              value: data.semester),
          const SizedBox(width: 16),
          _InfoChip(
              icon: Icons.person_outline,
              label: 'Login',
              value: data.login),
          const SizedBox(width: 16),
          _InfoChip(
              icon: Icons.class_outlined,
              label: 'Lớp',
              value: '${data.subjectClasses.length} lớp'),
          const SizedBox(width: 16),
          if (_fgData != null)
            _InfoChip(
                icon: Icons.people_outline,
                label: 'Sinh viên',
                value: '${_fgData!.subjectClasses.fold<int>(0, (sum, sc) => sum + sc.students.length)} SV'),
        ],
      ),
    );
  }

  // ── Dropdown chọn lớp ─────────────────────────────────────

  Widget _buildClassSelector() {
    if (_fgData == null) return const SizedBox.shrink();
    return Container(
      color: const Color(0xFF0D1117),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          const Text(
            'Lớp:',
            style: TextStyle(
                color: Color(0xFF8B949E),
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              border: Border.all(color: const Color(0xFF30363D)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: DropdownButton<SubjectClassResult>(
              value: _selectedClass,
              dropdownColor: const Color(0xFF161B22),
              underline: const SizedBox.shrink(),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: _fgData!.subjectClasses.map((sc) {
                return DropdownMenuItem<SubjectClassResult>(
                  value: sc,
                  child: Text(
                    sc.label,
                    style: const TextStyle(color: Colors.white),
                  ),
                );
              }).toList(),
              onChanged: _onClassChanged,
            ),
          ),
        ],
      ),
    );
  }

  // ── DataTable hiển thị sinh viên ──────────────────────────

  Widget _buildClassTabs() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: const Color(0xFF0D1117),
            child: const TabBar(
              isScrollable: true,
              labelColor: Color(0xFFE6EDF3),
              unselectedLabelColor: Color(0xFF8B949E),
              indicatorColor: Color(0xFF1F6FEB),
              tabs: [
                Tab(text: 'Thông tin nhóm'),
                Tab(text: 'Thông tin khóa luận'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildDataTable(),
                _buildThesisReviewTable(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable() {
    final students = _selectedClass?.students ?? [];
    final components = _gradeComponents;

    if (students.isEmpty) {
      return const Center(
        child: Text(
          'Lớp này không có sinh viên.',
          style: TextStyle(color: Color(0xFF8B949E)),
        ),
      );
    }

    return ScrollConfiguration(
      behavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.unknown,
        },
      ),
      child: Scrollbar(
        controller: _infoHorizontalController,
        thumbVisibility: false,
        trackVisibility: false,
        interactive: true,
        child: SingleChildScrollView(
          controller: _infoHorizontalController,
          scrollDirection: Axis.horizontal,
          child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF161B22)),
          dataRowColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return const Color(0xFF21262D);
            }
            return Colors.transparent;
          }),
          dividerThickness: 0.5,
          border: TableBorder(
            horizontalInside: const BorderSide(
                color: Color(0xFF21262D), width: 0.5),
            bottom: const BorderSide(color: Color(0xFF21262D), width: 0.5),
          ),
          headingTextStyle: const TextStyle(
            color: Color(0xFF8B949E),
            fontWeight: FontWeight.w600,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
          dataTextStyle: const TextStyle(
            color: Color(0xFFE6EDF3),
            fontSize: 13,
          ),
          columns: [
            _col('STT', width: 48),
            _col('Roll', width: 100),
            _col('Tên sinh viên', width: 200),
            // Thêm cột cho từng grade component
            for (final comp in components) _col(comp, width: 130),
            _col('Comment', width: 200),
            _col('Agree_to_defense', width: 140),
            _col('Revised_for_the_second_defennse', width: 240),
            _col('Disagree_to_defense', width: 160),
            _col('Note', width: 200),
          ],
          rows: students.map((stu) {
            final agree = _gradeByAlias(stu, const ['agree_to_defense']);
            final revised = _gradeByAlias(stu, const ['revised_for_the_second_defense', 'revised_for_the_second_defennse']);
            final disagree = _gradeByAlias(stu, const ['disagree_to_defense', 'disagree_to_defend']);
            final note = _gradeByAlias(stu, const ['note', 'ai_note']);
            return DataRow(
              cells: [
                DataCell(Text(
                  '${stu.stt}',
                  style: const TextStyle(color: Color(0xFF8B949E)),
                )),
                DataCell(_RollCell(roll: stu.roll)),
                DataCell(Text(stu.name)),
                // Điểm từng thành phần
                for (final comp in components)
                  DataCell(_GradeCell(
                    grade: stu.grades
                        .firstWhere(
                          (g) => g.component == comp,
                          orElse: () =>
                              const GradeComponentRecord(component: '', grade: ''),
                        )
                        .grade,
                  )),
                DataCell(
                  SizedBox(
                    width: 200,
                    child: Text(
                      _manualInfo(stu.roll, 'comment', stu.comment).trim().isEmpty
                          ? '—'
                          : _manualInfo(stu.roll, 'comment', stu.comment).trim(),
                      style: const TextStyle(color: Color(0xFFE6EDF3)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text(_safe(_manualInfo(stu.roll, 'agree', agree)))),
                DataCell(Text(_safe(_manualInfo(stu.roll, 'revised', revised)))),
                DataCell(Text(_safe(_manualInfo(stu.roll, 'disagree', disagree)))),
                DataCell(Row(
                  children: [
                    Expanded(child: Text(_safe(_manualInfo(stu.roll, 'note', note)))),
                    IconButton(
                      tooltip: 'Edit',
                      onPressed: () => _editInfoForStudent(
                        stu,
                        comment: _manualInfo(stu.roll, 'comment', stu.comment),
                        agree: _manualInfo(stu.roll, 'agree', agree),
                        revised: _manualInfo(stu.roll, 'revised', revised),
                        disagree: _manualInfo(stu.roll, 'disagree', disagree),
                        note: _manualInfo(stu.roll, 'note', note),
                      ),
                      icon: const Icon(Icons.edit, size: 16, color: Color(0xFF8B949E)),
                    ),
                  ],
                )),
              ],
            );
          }).toList(),
          ),
        ),
      ),
    );
  }

  String _gradeByAlias(StudentRecord stu, List<String> aliases) {
    final aliasSet = aliases.map((e) => e.trim().toLowerCase()).toSet();
    for (final g in stu.grades) {
      if (aliasSet.contains(g.component.trim().toLowerCase())) {
        return g.grade.trim();
      }
    }
    return '';
  }

  String _safe(String v) => v.trim().isEmpty ? '—' : v.trim();

  Widget _buildThesisReviewTable() {
    final students = _selectedClass?.students ?? [];

    if (students.isEmpty) {
      return const Center(
        child: Text(
          'Lớp này không có sinh viên.',
          style: TextStyle(color: Color(0xFF8B949E)),
        ),
      );
    }

    final first = students.first;
    final titleVi = _gradeByAlias(first, const ['vietnamese_title', 'title_vn', 'Tên khóa luận (Tiếng Việt)']);
    final titleEn = _gradeByAlias(first, const ['english_title', 'title_en', 'Tên khóa luận (Tiếng Anh)']);
    final contentReview = _gradeByAlias(first, const ['content_review', 'Nhận xét GV về nội dung khóa luận']);
    final formReview = _gradeByAlias(first, const ['format_review', 'Nhận xét GV về hình thức khóa luận']);
    final attitudeReview = _gradeByAlias(first, const ['attitude_review', 'Nhận xét GV về thái độ sinh viên']);
    final achievement = _gradeByAlias(first, const ['achievement_level', 'Kết luận - Mức độ đạt yêu cầu']);
    final limitation = _gradeByAlias(first, const ['limitation', 'Kết luận - Hạn chế']);
    final contributionRatio = _gradeByAlias(first, const ['contribution_ratio', 'contribution', 'Tỉ lệ đóng góp']);
    final groupId = _gradeByAlias(first, const ['group_id', 'group_code', 'Mã nhóm']);
    final thesisId = _gradeByAlias(first, const ['thesis_id', 'topic_id', 'Mã đề tài']);

    return Scrollbar(
      controller: _reviewHorizontalController,
      thumbVisibility: false,
      trackVisibility: false,
      interactive: true,
      child: SingleChildScrollView(
        controller: _reviewHorizontalController,
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF161B22)),
          dataRowColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return const Color(0xFF21262D);
            return Colors.transparent;
          }),
          dividerThickness: 0.5,
          border: TableBorder(
            horizontalInside: const BorderSide(color: Color(0xFF21262D), width: 0.5),
            bottom: const BorderSide(color: Color(0xFF21262D), width: 0.5),
          ),
          headingTextStyle: const TextStyle(
            color: Color(0xFF8B949E),
            fontWeight: FontWeight.w600,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
          dataTextStyle: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 13),
          columns: [
            _col('Mã nhóm', width: 120),
            _col('Mã đề tài', width: 120),
            _col('Tên khóa luận (Tiếng Việt)', width: 220),
            _col('Tên khóa luận (Tiếng Anh)', width: 220),
            _col('Nhận xét GV về nội dung khóa luận', width: 260),
            _col('Nhận xét GV về hình thức khóa luận', width: 260),
            _col('Nhận xét GV về thái độ sinh viên', width: 240),
            _col('Kết luận - Mức độ đạt yêu cầu', width: 220),
            _col('Kết luận - Hạn chế', width: 220),
            _col('Tỉ lệ đóng góp', width: 140),
          ],
          rows: [
            DataRow(cells: [
              DataCell(SizedBox(width: 120, child: Text(_safe(groupId)))),
              DataCell(SizedBox(width: 120, child: Text(_safe(thesisId)))),
              DataCell(SizedBox(width: 220, child: Text(_safe(titleVi)))),
              DataCell(SizedBox(width: 220, child: Text(_safe(titleEn)))),
              DataCell(SizedBox(width: 260, child: Text(_safe(contentReview)))),
              DataCell(SizedBox(width: 260, child: Text(_safe(formReview)))),
              DataCell(SizedBox(width: 240, child: Text(_safe(attitudeReview)))),
              DataCell(SizedBox(width: 220, child: Text(_safe(achievement)))),
              DataCell(SizedBox(width: 220, child: Text(_safe(limitation)))),
              DataCell(SizedBox(width: 140, child: Text(_safe(contributionRatio)))),
            ]),
          ],
        ),
      ),
    );
  }

  DataColumn _col(String label, {double width = 120}) {
    return DataColumn(
      label: SizedBox(
        width: width,
        child: Text(label.toUpperCase()),
      ),
    );
  }

  // ── Empty State ────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: const Icon(
              Icons.description_outlined,
              size: 56,
              color: Color(0xFF388BFD),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Chưa có file nào được mở',
            style: TextStyle(
              color: Color(0xFFE6EDF3),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Nhấn "Import .FG" để chọn file và xem dữ liệu chấm điểm.',
            style: TextStyle(color: Color(0xFF8B949E), fontSize: 14),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _importFile,
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: const Text('Import .FG'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF238636),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
              textStyle: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ── Error Banner ───────────────────────────────────────────

  Widget _buildErrorBanner() {
    return Container(
      color: const Color(0xFF3D1F1F),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: Color(0xFFF85149), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style:
                  const TextStyle(color: Color(0xFFF85149), fontSize: 13),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _errorMessage = null),
            icon: const Icon(Icons.close, size: 16),
            color: const Color(0xFFF85149),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetErrorBanner() {
    return Container(
      color: const Color(0xFF5C3B00),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFFFC107), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              _lastSheetError ?? 'Unknown Google Sheet error',
              style: const TextStyle(color: Color(0xFFFFE082), fontSize: 12),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _lastSheetError = null),
            icon: const Icon(Icons.close, size: 16),
            color: const Color(0xFFFFC107),
          ),
        ],
      ),
    );
  }

}

// ═══════════════════════════════════════════════════════════
// Helper Widgets
// ═══════════════════════════════════════════════════════════

class _TopBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _TopBarButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: Colors.white),
      label: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      style: TextButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoChip(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF8B949E)),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFE6EDF3),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _RollCell extends StatelessWidget {
  final String roll;
  const _RollCell({required this.roll});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2D3D),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2188FF).withAlpha(102)),
      ),
      child: Text(
        roll,
        style: const TextStyle(
          color: Color(0xFF79C0FF),
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    );
  }
}

class _GradeCell extends StatelessWidget {
  final String grade;
  const _GradeCell({required this.grade});

  Color get _color {
    if (grade.isEmpty) return const Color(0xFF30363D);
    final d = double.tryParse(grade);
    if (d == null) return const Color(0xFF8B949E);
    if (d >= 8.0) return const Color(0xFF3FB950); // Xanh
    if (d >= 5.0) return const Color(0xFFD29922); // Vàng
    return const Color(0xFFF85149);                // Đỏ
  }

  @override
  Widget build(BuildContext context) {
    return grade.isEmpty
        ? const Text('—', style: TextStyle(color: Color(0xFF30363D)))
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _color.withAlpha(38),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _color.withAlpha(102)),
            ),
            child: Text(
              grade,
              style: TextStyle(
                color: _color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          );
  }
}


class _AiResultRow extends StatelessWidget {
  final Map<String, dynamic> item;
  const _AiResultRow({required this.item});

  Color get _decisionColor {
    if (item['ok'] != true) return const Color(0xFFF85149);
    switch (item['decision'] as String? ?? '') {
      case 'agree_to_defense':
        return const Color(0xFF3FB950);
      case 'revised_for_the_second_defense':
        return const Color(0xFFD29922);
      case 'disagree_to_defend':
        return const Color(0xFFF85149);
      default:
        return const Color(0xFF8B949E);
    }
  }

  String get _decisionLabel {
    if (item['ok'] != true) return 'Lỗi';
    switch (item['decision'] as String? ?? '') {
      case 'agree_to_defense':
        return 'Đồng ý bảo vệ';
      case 'revised_for_the_second_defense':
        return 'Bảo vệ lần 2';
      case 'disagree_to_defend':
        return 'Không đủ điều kiện';
      default:
        return item['decision'] as String? ?? '?';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2D3D),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF2188FF).withAlpha(102)),
            ),
            child: Text(
              item['roll'] as String? ?? '?',
              style: const TextStyle(
                color: Color(0xFF79C0FF),
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((item['name'] as String? ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      item['name'] as String,
                      style: const TextStyle(
                        color: Color(0xFFE6EDF3),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _decisionColor.withAlpha(38),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _decisionColor.withAlpha(102)),
                  ),
                  child: Text(
                    _decisionLabel,
                    style: TextStyle(
                      color: _decisionColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (item['ok'] != true) ...[
                  const SizedBox(height: 4),
                  Text(
                    item['error'] as String? ?? '',
                    style: const TextStyle(color: Color(0xFFF85149), fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EvaluatingDialog extends StatelessWidget {
  final String fileName;
  final ValueNotifier<int> elapsed;

  const _EvaluatingDialog({required this.fileName, required this.elapsed});

  String _fmt(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF6E40C9), width: 1),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: Color(0xFF8957E5),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'AI đang phân tích khóa luận...',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              fileName,
              style: const TextStyle(
                color: Color(0xFF8B949E),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<int>(
              valueListenable: elapsed,
              builder: (_, secs, child) => Text(
                'Đã chờ: ${_fmt(secs)}',
                style: const TextStyle(
                  color: Color(0xFF8957E5),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ollama đang chạy mô hình AI cho từng sinh viên.\nQuá trình này có thể mất vài phút.',
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 12, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _LoadingWidget extends StatelessWidget {
  const _LoadingWidget();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF2188FF),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Đang đọc file .fg...',
          style: TextStyle(color: Color(0xFF8B949E), fontSize: 14),
        ),
      ],
    );
  }
}

// ── Widget hiển thị 1 tab đã tạo CMT thành công ───────────────────────────
class _ImportResultSuccessRow extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ImportResultSuccessRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final sheetName  = item['sheetName']?.toString() ?? '';
    final cmtPath    = item['cmtFilePath']?.toString() ?? '';
    final displayPath = cmtPath.replaceAll('\\', '/').split('/').last;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF238636).withAlpha(120)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF3FB950), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sheetName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (displayPath.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    displayPath,
                    style: const TextStyle(
                      color: Color(0xFF3FB950),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widget hiển thị 1 tab bị cảnh báo thiếu dữ liệu ──────────────────────
class _ImportResultWarningRow extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ImportResultWarningRow({required this.item});

  // Ánh xạ field key → tên cột tiếng Việt thân thiện
  static const _fieldLabels = <String, String>{
    'roll':        'Mã sinh viên (Roll)',
    'name':        'Họ tên sinh viên',
    'titleVN':     'Tên khóa luận (Tiếng Việt)',
    'titleEN':     'Tên khóa luận (Tiếng Anh)',
    'content':     'Nhận xét GV về nội dung',
    'form':        'Nhận xét GV về hình thức',
    'attitude':    'Nhận xét GV về thái độ sinh viên',
    'achievement': 'Kết luận - Mức độ đạt yêu cầu',
    'limitation':  'Kết luận - Hạn chế',
  };

  @override
  Widget build(BuildContext context) {
    final sheetName = item['sheetName']?.toString() ?? '';
    final message   = item['message']?.toString() ?? 'Thiếu dữ liệu bắt buộc.';
    final rawWarnings = (item['warnings'] as List?) ?? [];
    final warnings = rawWarnings.whereType<Map<String, dynamic>>().toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD29922).withAlpha(130)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header của tab
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFD29922).withAlpha(20),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFD29922), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sheetName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message,
                        style: const TextStyle(color: Color(0xFFD29922), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Danh sách sinh viên thiếu field
          if (warnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sinh viên cần điền thêm:',
                    style: TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  ...warnings.map((w) {
                    final roll = w['roll']?.toString() ?? '?';
                    final name = w['name']?.toString() ?? '?';
                    final missing = ((w['missingFields'] as List?) ?? [])
                        .map((f) => _fieldLabels[f.toString()] ?? f.toString())
                        .join(', ');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ', style: TextStyle(color: Color(0xFFD29922), fontSize: 12)),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 12, height: 1.4),
                                children: [
                                  TextSpan(
                                    text: '$roll — $name\n',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'Thiếu: $missing',
                                    style: const TextStyle(color: Color(0xFFDA3633)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }
}


