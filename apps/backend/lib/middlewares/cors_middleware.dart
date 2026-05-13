import 'package:shelf/shelf.dart';

Handler addCorsHeaders(Handler handler) {
  return (Request request) async {
    if (request.method == 'OPTIONS') {
      return Response.ok('', headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Origin, Content-Type',
      });
    }
    final response = await handler(request);
    return response.change(headers: {
      'Access-Control-Allow-Origin': '*',
    });
  };
}
