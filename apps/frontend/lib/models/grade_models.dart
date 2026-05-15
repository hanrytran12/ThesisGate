// ============================================================
// grade_models.dart
// Dart models khớp 100% với JSON output từ decoder.exe (Phase 1)
// ============================================================

/// Root object của file .fg sau khi decode
class FgOutput {
  final String typeName;
  final String version;
  final String semester;
  final String login;
  final List<SubjectClassResult> subjectClasses;

  const FgOutput({
    required this.typeName,
    required this.version,
    required this.semester,
    required this.login,
    required this.subjectClasses,
  });

  factory FgOutput.fromJson(Map<String, dynamic> json) {
    return FgOutput(
      typeName:      json['typeName'] as String? ?? '',
      version:       json['version']  as String? ?? '',
      semester:      json['semester'] as String? ?? '',
      login:         json['login']    as String? ?? '',
      subjectClasses: (json['subjectClasses'] as List<dynamic>? ?? [])
          .map((e) => SubjectClassResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'typeName':      typeName,
        'version':       version,
        'semester':      semester,
        'login':         login,
        'subjectClasses': subjectClasses.map((e) => e.toJson()).toList(),
      };
}

/// Một lớp môn học (vd: PRN221 / NET1710)
class SubjectClassResult {
  final String subject; // Tên môn học, vd: "PRN221"
  final String classCode; // Mã lớp, vd: "NET1710"
  final List<StudentRecord> students;

  const SubjectClassResult({
    required this.subject,
    required this.classCode,
    required this.students,
  });

  /// Label hiển thị: "PRN221 / NET1710"
  String get label => '$subject / $classCode';

  factory SubjectClassResult.fromJson(Map<String, dynamic> json) {
    return SubjectClassResult(
      subject:   json['subject'] as String? ?? '',
      classCode: json['class']   as String? ?? '',
      students:  (json['students'] as List<dynamic>? ?? [])
          .map((e) => StudentRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'subject':  subject,
        'class':    classCode,
        'students': students.map((e) => e.toJson()).toList(),
      };
}

/// Một sinh viên trong lớp
class StudentRecord {
  final int stt;
  final String roll;
  final String name;
  final String comment;
  final List<GradeComponentRecord> grades;

  const StudentRecord({
    required this.stt,
    required this.roll,
    required this.name,
    required this.comment,
    required this.grades,
  });

  factory StudentRecord.fromJson(Map<String, dynamic> json) {
    return StudentRecord(
      stt:     json['stt']     as int?    ?? 0,
      roll:    json['roll']    as String? ?? '',
      name:    json['name']    as String? ?? '',
      comment: json['comment'] as String? ?? '',
      grades:  (json['grades'] as List<dynamic>? ?? [])
          .map((e) => GradeComponentRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'stt':     stt,
        'roll':    roll,
        'name':    name,
        'comment': comment,
        'grades':  grades.map((e) => e.toJson()).toList(),
      };
}

/// Một thành phần điểm (Final Exam, Implementation, v.v.)
class GradeComponentRecord {
  final String component;
  final String grade;

  const GradeComponentRecord({
    required this.component,
    required this.grade,
  });

  factory GradeComponentRecord.fromJson(Map<String, dynamic> json) {
    return GradeComponentRecord(
      component: json['component'] as String? ?? '',
      grade:     json['grade']     as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'component': component,
        'grade':     grade,
      };
}
