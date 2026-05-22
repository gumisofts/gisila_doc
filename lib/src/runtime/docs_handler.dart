/// Builds a shelf [Handler] that exposes the OpenAPI document and a
/// CDN-hosted Swagger UI / ReDoc page.
library gisila_doc.runtime.docs_handler;

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'spec.dart';

/// Returns a [Router] that serves the spec and a docs UI.
///
/// Routes mounted (paths relative to wherever the handler is mounted):
///
/// * `GET /openapi.json` - the rendered OpenAPI 3.1 document.
/// * `GET /docs`         - Swagger UI page.
/// * `GET /docs/`        - same as `/docs` (with trailing slash).
/// * `GET /redoc`        - ReDoc page (handy alternative).
///
/// The [specPath] passed to the UI pages defaults to `'./openapi.json'`
/// so the UI works whether the docs router is mounted at `/` or under
/// any prefix.
Handler docsHandler(
  OpenApiSpec spec, {
  String specPath = './openapi.json',
  String swaggerTitle = 'API Docs',
}) {
  final router = Router()
    ..get('/openapi.json', (Request request) {
      return Response.ok(
        spec.toJson(),
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-cache',
        },
      );
    })
    ..get('/docs', (Request request) {
      return Response.ok(
        _swaggerHtml(specPath: specPath, title: swaggerTitle),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    })
    ..get('/docs/', (Request request) {
      return Response.ok(
        _swaggerHtml(specPath: specPath, title: swaggerTitle),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    })
    ..get('/redoc', (Request request) {
      return Response.ok(
        _redocHtml(specPath: specPath, title: swaggerTitle),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });

  return router.call;
}

String _swaggerHtml({required String specPath, required String title}) => '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$title</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
  <style>html,body{margin:0;padding:0;background:#fafafa}</style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js" crossorigin></script>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-standalone-preset.js" crossorigin></script>
  <script>
    window.addEventListener('load', function () {
      window.ui = SwaggerUIBundle({
        url: '$specPath',
        dom_id: '#swagger-ui',
        deepLinking: true,
        presets: [
          SwaggerUIBundle.presets.apis,
          SwaggerUIStandalonePreset
        ],
        layout: 'StandaloneLayout',
        persistAuthorization: true
      });
    });
  </script>
</body>
</html>
''';

String _redocHtml({required String specPath, required String title}) => '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$title</title>
  <style>html,body{margin:0;padding:0}</style>
</head>
<body>
  <redoc spec-url="$specPath"></redoc>
  <script src="https://cdn.redoc.ly/redoc/latest/bundles/redoc.standalone.js"></script>
</body>
</html>
''';
