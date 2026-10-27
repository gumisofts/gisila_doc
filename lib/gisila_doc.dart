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
///   final app = GisilaApp(config: AppConfig());
///   app.registerController(attacher: (app, router, {prefix = ''}) {
///     UsersController().attachToApp(app, router, spec, prefix: prefix);
///     router.mount('/', docsHandler(spec)); // /docs, /redoc, /openapi.json
///   });
///   await app.start(port: 8080);
/// }
/// ```
///
/// Each `@Controller` class generates an
/// `attachToApp(app, router, spec, {prefix})` extension method via
/// build_runner; run `dart run build_runner build` to refresh after
/// changing annotations.
library gisila_doc;

// Re-export the gisila runtime so a single
// `import 'package:gisila_doc/gisila_doc.dart';` is enough.
// Hide gisila's annotation set whose names overlap with the doc-aware
// versions defined in `src/annotations.dart` (Controller, Route,
// Get/Post/Put/Patch/Delete/Head/Options, Body, Query, Path, Header).
export 'package:gisila/gisila.dart'
    hide
        Body,
        Controller,
        Delete,
        Get,
        Head,
        Header,
        Options,
        Patch,
        Path,
        Post,
        Put,
        Query,
        Route;

export 'src/annotations.dart';
export 'src/runtime/codec.dart'
    show BadRequestException, coerce, emptyResponse, jsonResponse, readJsonBody;
export 'src/runtime/docs_handler.dart' show docsHandler;
export 'src/runtime/spec.dart';
