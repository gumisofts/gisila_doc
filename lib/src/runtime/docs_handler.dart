/// Builds a shelf [Handler] that exposes the OpenAPI document and a
/// CDN-hosted Swagger UI / ReDoc page.
library gisila_doc.runtime.docs_handler;

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'spec.dart';

/// Returns a [Router] that serves the spec and both documentation UIs.
///
/// Routes mounted (paths relative to wherever the handler is mounted):
///
/// * `GET /openapi.json` - the rendered OpenAPI 3.1 document.
/// * `GET /docs`         - Swagger UI page (`/docs/` redirects here).
/// * `GET /redoc`        - Redocly page (`/redoc/` redirects here).
///
/// Links between the pages and to the spec are built from the mount point
/// (`Request.handlerPath`), so they work at `/` and under any prefix.
/// [specPath] overrides the spec URL the UIs load: an absolute path or URL
/// is used as is, a relative one is resolved against the mount point.
///
/// The UIs load Swagger UI and Redoc from unpkg at pinned versions with
/// Subresource Integrity, so a changed or compromised CDN file is refused
/// by the browser. Set [enabled] to `false` (for example in production) to
/// answer every route with `404`.
///
/// [title] sets the browser `<title>` used by both UIs. Pass
/// [swaggerTitle] or [redocTitle] to override it for a specific UI.
Handler docsHandler(
  OpenApiSpec spec, {
  String? specPath,
  String title = 'API Docs',
  String? swaggerTitle,
  String? redocTitle,
  bool enabled = true,
}) {
  if (!enabled) return (Request request) => Response.notFound('Not Found');
  final swTitle = swaggerTitle ?? title;
  final rdTitle = redocTitle ?? title;

  String specUrl(Request request) {
    final base = request.handlerPath;
    final p = specPath;
    if (p == null) return '${base}openapi.json';
    if (p.startsWith('/') || Uri.tryParse(p)?.hasScheme == true) return p;
    return '$base${p.startsWith('./') ? p.substring(2) : p}';
  }

  Response html(String body) =>
      Response.ok(body, headers: {'content-type': 'text/html; charset=utf-8'});

  Response redirectWithoutSlash(Request request, String page) =>
      Response.movedPermanently('${request.handlerPath}$page');

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
      return html(_swaggerHtml(
          specUrl: specUrl(request),
          otherUrl: '${request.handlerPath}redoc',
          title: swTitle));
    })
    ..get('/docs/', (Request r) => redirectWithoutSlash(r, 'docs'))
    ..get('/redoc', (Request request) {
      return html(_redocHtml(
          specUrl: specUrl(request),
          otherUrl: '${request.handlerPath}docs',
          title: rdTitle));
    })
    ..get('/redoc/', (Request r) => redirectWithoutSlash(r, 'redoc'));

  return router.call;
}

// Pinned UI assets. To upgrade, change the version and recompute each hash:
// curl -sL <url> | openssl dgst -sha384 -binary | openssl base64 -A
const _swaggerBase = 'https://unpkg.com/swagger-ui-dist@5.33.1';
const _swaggerCssSri =
    'sha384-Ov4/wv3j2bmct8cDc5X4ngJZohVPzEmc6uDPH8WeljUxO5vtoykvMEfbu9Vh6RaW';
const _swaggerBundleSri =
    'sha384-ZPehFMQommnnuaZ4rpxgkgTT2DKFVp4hZC/7pLit+9Lek9T1YGSo23eHFbvNkXkw';
const _swaggerPresetSri =
    'sha384-My2aDM4r2Mbm3ybHcubKm9O9U8FEjvF/O5nGvE9YK5dzqOTbWEKa79RPJ1krdMaF';
const _redocJs = 'https://unpkg.com/redoc@2.5.4/bundles/redoc.standalone.js';
const _redocSri =
    'sha384-w447zOpYfw/1Tv/5AK9NfHTlQIqE3RVR6KY62jCyy9zNDgO64cMwGGP1Fj0zJVf5';

/// [s] for HTML text and attribute values.
String _html(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// [s] as a JavaScript string literal that is also safe inside <script>.
String _js(String s) => jsonEncode(s).replaceAll('<', r'\u003c');

String _swaggerHtml({
  required String specUrl,
  required String otherUrl,
  required String title,
}) =>
    '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${_html(title)}</title>
  <link rel="stylesheet" href="$_swaggerBase/swagger-ui.css"
        integrity="$_swaggerCssSri" crossorigin="anonymous" />
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
    <span>${_html(title)}</span>
    <a href="${_html(otherUrl)}">Redoc</a>
  </div>
  <div id="swagger-ui"></div>
  <script src="$_swaggerBase/swagger-ui-bundle.js"
          integrity="$_swaggerBundleSri" crossorigin="anonymous"></script>
  <script src="$_swaggerBase/swagger-ui-standalone-preset.js"
          integrity="$_swaggerPresetSri" crossorigin="anonymous"></script>
  <script>
    window.addEventListener('load', function () {
      window.ui = SwaggerUIBundle({
        url: ${_js(specUrl)},
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

String _redocHtml({
  required String specUrl,
  required String otherUrl,
  required String title,
}) =>
    '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${_html(title)}</title>
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
    <span>${_html(title)}</span>
    <a href="${_html(otherUrl)}">Swagger UI</a>
  </div>
  <div id="redoc-container"></div>
  <script src="$_redocJs"
          integrity="$_redocSri" crossorigin="anonymous"></script>
  <script>
    Redoc.init(
      ${_js(specUrl)},
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
