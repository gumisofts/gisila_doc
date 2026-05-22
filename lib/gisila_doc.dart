/// Generate OpenAPI 3.1 specs and shelf_router wiring from annotated
/// Dart controllers.
///
/// Quick start:
///
/// ```dart
/// import 'package:shelf/shelf.dart';
/// import 'package:shelf/shelf_io.dart' as io;
/// import 'package:shelf_router/shelf_router.dart';
/// import 'package:gisila_doc/gisila_doc.dart';
///
/// import 'controllers/users_controller.dart';
///
/// Future<void> main() async {
///   final spec = OpenApiSpec(
///     info: ApiInfo(title: 'Demo API', version: '1.0.0'),
///   );
///
///   final router = Router();
///   UsersController().attachOpenApi(spec, router);
///   router.mount('/', docsHandler(spec));
///
///   await io.serve(router.call, '0.0.0.0', 8080);
/// }
/// ```
///
/// Each `@Controller` class generates an `attachOpenApi(spec, router)`
/// extension method via build_runner; run `dart run build_runner build`
/// to refresh after changing annotations.
library gisila_doc;

export 'src/annotations.dart';
export 'src/runtime/codec.dart'
    show BadRequestException, coerce, emptyResponse, jsonResponse, readJsonBody;
export 'src/runtime/docs_handler.dart' show docsHandler;
export 'src/runtime/spec.dart';
