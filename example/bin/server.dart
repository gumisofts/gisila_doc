import 'package:gisila_doc/gisila_doc.dart';
import 'package:gisila_doc_example/controllers/users_controller.dart';
import 'package:gisila_doc_example/services/user_service.dart';

Future<void> main() async {
  final spec = OpenApiSpec(
    info: const ApiInfo(
      title: 'Demo API',
      version: '1.0.0',
      description: 'A tiny API generated end-to-end by gisila_doc.',
    ),
    servers: const [ApiServer(url: 'http://localhost:8080')],
  );

  final app = GisilaApp(
    config: AppConfig(
      logLevel: LogLevel.info,
      defaultRouteConfig: const RouteConfig(
        rateLimit: RateLimitConfig(requestsPerMinute: 300),
      ),
    ),
  );

  app.registerService<UserService>(UserService.new);

  final router = Router();

  // Generated extension - registers routes via gisilaRoute(...) AND
  // populates the OpenAPI spec.
  UsersController().attachToApp(app, router, spec);

  // /openapi.json + /docs (Swagger UI) + /redoc
  router.mount('/', docsHandler(spec));

  app.registerController(attacher: (app, mainRouter, {String prefix = ''}) {
    mainRouter.mount('/', router.call);
  });

  await app.start(host: '0.0.0.0', port: 8080);
  print('  Swagger UI:    http://localhost:8080/docs');
  print('  ReDoc:         http://localhost:8080/redoc');
  print('  OpenAPI JSON:  http://localhost:8080/openapi.json');
}
