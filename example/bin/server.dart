import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:gisila_doc/gisila_doc.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:gisila_doc_example/controllers/users_controller.dart';

Future<void> main() async {
  final spec = OpenApiSpec(
    info: const ApiInfo(
      title: 'Demo API',
      version: '1.0.0',
      description: 'A tiny API generated end-to-end by gisila_doc.',
    ),
    servers: const [ApiServer(url: 'http://localhost:8080')],
  );

  final router = Router();

  // Generated extension - registers routes AND populates the spec.
  UsersController().attachOpenApi(spec, router);

  // /openapi.json + /docs (Swagger UI) + /redoc
  router.mount('/', docsHandler(spec));

  final handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(router.call);

  final server = await io.serve(handler, '0.0.0.0', 8080);
  print('Listening on http://${server.address.host}:${server.port}');
  print('  Swagger UI:    http://localhost:${server.port}/docs');
  print('  ReDoc:         http://localhost:${server.port}/redoc');
  print('  OpenAPI JSON:  http://localhost:${server.port}/openapi.json');
}
