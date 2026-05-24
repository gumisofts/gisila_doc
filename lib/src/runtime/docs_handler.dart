/// Builds a shelf [Handler] that exposes the OpenAPI document and a
/// CDN-hosted Swagger UI / ReDoc page.
library gisila_doc.runtime.docs_handler;

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'spec.dart';

/// Returns a [Router] that serves the spec and both documentation UIs.
///
/// Routes mounted (paths relative to wherever the handler is mounted):
///
/// * `GET /openapi.json` - the rendered OpenAPI 3.1 document.
/// * `GET /docs`         - Swagger UI page.
/// * `GET /docs/`        - same as `/docs` (with trailing slash).
/// * `GET /redoc`        - Redocly page.
/// * `GET /redoc/`       - same as `/redoc` (with trailing slash).
///
/// The [specPath] passed to the UI pages defaults to `'./openapi.json'`
/// so the UI works whether the docs router is mounted at `/` or under
/// any prefix.
///
/// [title] sets the browser `<title>` used by both UIs. Pass
/// [swaggerTitle] or [redocTitle] to override it for a specific UI.
Handler docsHandler(
  OpenApiSpec spec, {
  String specPath = './openapi.json',
  String title = 'API Docs',
  String? swaggerTitle,
  String? redocTitle,
}) {
  final swTitle = swaggerTitle ?? title;
  final rdTitle = redocTitle ?? title;

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
        _swaggerHtml(specPath: specPath, title: swTitle),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    })
    ..get('/docs/', (Request request) {
      return Response.ok(
        _swaggerHtml(specPath: specPath, title: swTitle),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    })
    ..get('/redoc', (Request request) {
      return Response.ok(
        _redocHtml(specPath: specPath, title: rdTitle),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    })
    ..get('/redoc/', (Request request) {
      return Response.ok(
        _redocHtml(specPath: specPath, title: rdTitle),
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
  <style>
    html, body { margin: 0; padding: 0; background: #fafafa; }
    #nav-bar {
      display: flex; align-items: center; gap: 12px;
      padding: 8px 16px; background: #1b1b1d; font-family: sans-serif;
    }
    #nav-bar span { color: #aaa; font-size: 13px; }
    #nav-bar a {
      color: #61dafb; font-size: 13px; text-decoration: none;
      border: 1px solid #61dafb; border-radius: 4px; padding: 3px 10px;
    }
    #nav-bar a:hover { background: #61dafb22; }
  </style>
</head>
<body>
  <div id="nav-bar">
    <span>$title</span>
    <a href="../redoc">Redoc</a>
  </div>
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
        persistAuthorization: true,
        tryItOutEnabled: true,
        filter: true,
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
  <style>
    html, body { margin: 0; padding: 0; }
    #nav-bar {
      display: flex; align-items: center; gap: 12px;
      padding: 8px 16px; background: #1b1b1d; font-family: sans-serif;
    }
    #nav-bar span { color: #aaa; font-size: 13px; }
    #nav-bar a {
      color: #61dafb; font-size: 13px; text-decoration: none;
      border: 1px solid #61dafb; border-radius: 4px; padding: 3px 10px;
    }
    #nav-bar a:hover { background: #61dafb22; }
    #redoc-container { height: calc(100vh - 41px); overflow: auto; }
  </style>
</head>
<body>
  <div id="nav-bar">
    <span>$title</span>
    <a href="../docs">Swagger UI</a>
  </div>
  <div id="redoc-container"></div>
  <script src="https://cdn.redoc.ly/redoc/latest/bundles/redoc.standalone.js"></script>
  <script>
    Redoc.init(
      '$specPath',
      {
        scrollYOffset: 41,
        hideDownloadButton: false,
        expandResponses: '200,201',
        requiredPropsFirst: true,
        sortPropsAlphabetically: false,
        hideHostname: false,
        noAutoAuth: false,
        pathInMiddlePanel: false,
        nativeScrollbars: false,
        theme: {
          colors: {
            primary: { main: '#61dafb' }
          },
          typography: {
            fontSize: '14px',
            fontFamily: 'Inter, system-ui, sans-serif',
            headings: {
              fontFamily: 'Inter, system-ui, sans-serif'
            },
            code: {
              fontFamily: 'JetBrains Mono, Fira Code, monospace',
              fontSize: '13px'
            }
          },
          sidebar: {
            width: '260px',
            backgroundColor: '#1a1a2e',
            textColor: '#e8eaf0',
            activeTextColor: '#ffffff'
          }
        }
      },
      document.getElementById('redoc-container')
    );
  </script>
</body>
</html>
''';
