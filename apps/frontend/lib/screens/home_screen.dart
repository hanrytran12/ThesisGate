// ============================================================
// home_screen.dart — Màn hình chính của ThesisGate
// Tính năng:
//   • Import file .fg → gọi decoder.exe → hiển thị DataTable
//   • Dropdown chọn lớp (SubjectClass)
//   • Hiển thị danh sách sinh viên với grades
//   • Nút Export (Phase 4 & 5)
// ============================================================

import 'package:flutter/material.dart';
import '../models/grade_models.dart';
import '../services/fg_parser_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ── State ──────────────────────────────────────────────────
  final _parserService = FgParserService();

  FgOutput?           _fgData;
  SubjectClassResult? _selectedClass;
  String?             _fileName;
  bool                _isLoading = false;
  String?             _errorMessage;

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
      _isLoading    = false;
    });
  }

  void _onClassChanged(SubjectClassResult? value) {
    setState(() => _selectedClass = value);
  }

  void _clearData() {
    setState(() {
      _fgData        = null;
      _selectedClass = null;
      _fileName      = null;
      _errorMessage  = null;
    });
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
          if (_fgData != null) ...[
            _buildInfoBar(),
            _buildClassSelector(),
            const Divider(color: Color(0xFF21262D), height: 1),
            Expanded(child: _buildDataTable()),
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
          if (_selectedClass != null)
            _InfoChip(
                icon: Icons.people_outline,
                label: 'Sinh viên',
                value: '${_selectedClass!.students.length} SV'),
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

    return SingleChildScrollView(
      child: SingleChildScrollView(
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
          ],
          rows: students.map((stu) {
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
                  Text(
                    stu.comment.isEmpty ? '—' : stu.comment,
                    style: TextStyle(
                      color: stu.comment.isEmpty
                          ? const Color(0xFF30363D)
                          : const Color(0xFFE6EDF3),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
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

