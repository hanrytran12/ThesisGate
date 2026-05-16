import 'package:shelf_router/shelf_router.dart';

import '../controllers/sheet_workflow_controller.dart';

class ApiRouter {
  final SheetWorkflowController _sheetWorkflowController = SheetWorkflowController();

  Router get router {
    final router = Router();

    // Định nghĩa các endpoints tại đây
    router.post('/workflow/sheet/validate', _sheetWorkflowController.validateSheet);
    router.post('/workflow/sheet/import/tabs', _sheetWorkflowController.listImportTabs);
    router.post('/workflow/sheet/import', _sheetWorkflowController.importSheet);

    return router;
  }
}
