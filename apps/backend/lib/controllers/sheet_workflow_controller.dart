import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import '../services/ai_evaluation_service.dart';
import '../services/sheet_validation_service.dart';

class SheetWorkflowController {
  final SheetValidationService _service = SheetValidationService();
  final AiEvaluationService _aiService = AiEvaluationService();

  Future<Response> validateSheet(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final sheetUrl = (payload['sheetUrl'] as String?)?.trim() ?? '';

      if (sheetUrl.isEmpty) {
        return _json(
          400,
          {
            'ok': false,
            'error': {
              'code': 'INVALID_INPUT',
              'message': 'sheetUrl là bắt buộc',
            },
          },
        );
      }

      final result = await _service.validateFromUrl(sheetUrl);
      return _json(200, result.toJson());
    } on FormatException catch (e) {
      return _json(
        400,
        {
          'ok': false,
          'error': {
            'code': 'INVALID_SHEET_URL',
            'message': e.message,
          },
        },
      );
    } catch (e) {
      return _json(
        500,
        {
          'ok': false,
          'error': {
            'code': 'VALIDATION_FAILED',
            'message': e.toString(),
          },
        },
      );
    }
  }

  Future<Response> listImportTabs(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final sheetUrl = (payload['sheetUrl'] as String?)?.trim() ?? '';

      if (sheetUrl.isEmpty) {
        return _json(400, {
          'ok': false,
          'error': {'code': 'INVALID_INPUT', 'message': 'sheetUrl là bắt buộc'}
        });
      }

      final tabs = await _service.getSepTabsFromUrl(sheetUrl);
      return _json(200, {'ok': true, 'tabs': tabs});
    } catch (e) {
      return _json(500, {
        'ok': false,
        'error': {'code': 'LIST_TABS_FAILED', 'message': e.toString()}
      });
    }
  }

  Future<Response> importSheet(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final sheetUrl = (payload['sheetUrl'] as String?)?.trim() ?? '';

      if (sheetUrl.isEmpty) {
        return _json(
          400,
          {
            'ok': false,
            'error': {
              'code': 'INVALID_INPUT',
              'message': 'sheetUrl là bắt buộc',
            },
          },
        );
      }

      final rawSheetNames = payload['sheetNames'];
      final sheetNames = rawSheetNames is List
          ? rawSheetNames.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
          : null;

      final result = await _service.importFromUrl(sheetUrl, sheetNames: sheetNames);
      return _json(200, result);
    } on FormatException catch (e) {
      return _json(
        400,
        {
          'ok': false,
          'error': {
            'code': 'INVALID_SHEET_URL',
            'message': e.message,
          },
        },
      );
    } catch (e) {
      return _json(
        500,
        {
          'ok': false,
          'error': {
            'code': 'IMPORT_FAILED',
            'message': e.toString(),
          },
        },
      );
    }
  }

  Future<Response> evaluateCmt(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final cmtJsonPath = (payload['cmtJsonPath'] as String?)?.trim() ?? '';

      if (cmtJsonPath.isEmpty) {
        return _json(400, {
          'ok': false,
          'error': {'code': 'INVALID_INPUT', 'message': 'cmtJsonPath là bắt buộc'},
        });
      }

      // Security: only allow paths within outputs/cmt/
      final outputsDir = p.normalize(p.join(Directory.current.path, 'outputs', 'cmt'));
      final resolvedPath = p.normalize(
        p.isAbsolute(cmtJsonPath) ? cmtJsonPath : p.join(outputsDir, cmtJsonPath),
      );
      if (!p.isWithin(outputsDir, resolvedPath)) {
        return _json(403, {
          'ok': false,
          'error': {'code': 'FORBIDDEN', 'message': 'Đường dẫn file không hợp lệ'},
        });
      }

      final result = await _aiService.evaluateAndRebuildCmt(resolvedPath);
      return _json(200, result);
    } catch (e) {
      return _json(500, {
        'ok': false,
        'error': {'code': 'EVALUATE_FAILED', 'message': e.toString()},
      });
    }
  }

  Response _json(int status, Map<String, dynamic> body) {
    return Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );
  }
}
