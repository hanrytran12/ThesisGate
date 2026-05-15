class SheetParseResult {
  final String spreadsheetId;
  final String? gid;

  SheetParseResult({required this.spreadsheetId, this.gid});
}

class ValidationErrorItem {
  final int? rowNumber;
  final String? column;
  final String? sheetGid;
  final String? sheetName;
  final String code;
  final String message;
  final String? value;

  ValidationErrorItem({
    required this.code,
    required this.message,
    this.rowNumber,
    this.column,
    this.sheetGid,
    this.sheetName,
    this.value,
  });

  Map<String, dynamic> toJson() => {
        'rowNumber': rowNumber,
        'column': column,
        'sheetGid': sheetGid,
        'sheetName': sheetName,
        'code': code,
        'message': message,
        'value': value,
      };
}

class ValidationSummary {
  final int totalRows;
  final int validRows;
  final int invalidRows;

  ValidationSummary({
    required this.totalRows,
    required this.validRows,
    required this.invalidRows,
  });

  Map<String, dynamic> toJson() => {
        'totalRows': totalRows,
        'validRows': validRows,
        'invalidRows': invalidRows,
      };
}

class SheetValidationResult {
  final bool ok;
  final ValidationSummary summary;
  final List<ValidationErrorItem> errors;

  SheetValidationResult({
    required this.ok,
    required this.summary,
    required this.errors,
  });

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'summary': summary.toJson(),
        'errors': errors.map((e) => e.toJson()).toList(),
      };
}
