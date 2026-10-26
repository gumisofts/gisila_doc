# Changelog

## Unreleased

- Docs UI (breaking defaults): links and the spec URL are absolute from
  where `docsHandler` is mounted, so `/docs/` and prefixed mounts work
  (`/docs/` and `/redoc/` now redirect to the page). `specPath` defaults to
  the mounted `openapi.json`; a relative value resolves against the mount.
  Swagger UI 5.33.1 and Redoc 2.5.4 load from unpkg at those exact versions
  with Subresource Integrity (Redoc used `latest` from its own CDN). New
  `enabled:` flag answers `404` when false. Titles are HTML-escaped.
- `OpenApiSpec.extra['components']` is merged into the generated
  components section by section instead of replacing them.
- Schemas: enums are `{type: string, enum: [names]}` (matching gisila,
  which now sends an enum's name), unless the enum defines `toJson()`;
  `Set<T>` and `Iterable<T>` are arrays, a `Set` with `uniqueItems: true`.
- Generated handlers: only parameter binding is wrapped in the
  `TypeError`/`FormatException` → `400` catch. An error thrown by the
  controller method itself used to come back as a `400` echoing its text;
  it now reaches the app's error handler (a `500`). Routes without
  parameters have no wrapper. Needs Dart 3 records (the SDK floor already is).
- OpenAPI: guarded routes now carry auth information. Operations from
  routes with `@RequireAuth`, `@Permissions`, `@AnyPermission` or `@Roles`
  (method or controller, unless `@Public`) get `security` (each of the new
  `OpenApiSpec.securitySchemes`, default a single `bearerAuth` HTTP bearer
  scheme, emitted only when something is guarded), a `401` and, with
  permissions or roles, a `403` using gisila's error body
  (`errorEnvelopeSchema`), plus `x-gisila-guards`. Routes' own
  `@ApiResponse` entries win. New `SecurityScheme`, and
  `Operation.requiresAuth` / `permissions` / `anyPermission` / `roles`.
  Re-run build_runner to pick this up.
- OpenAPI: generic classes no longer collapse into one schema.
  `Page<User>` and `Page<Post>` become `Page_User` and `Page_Post`, with
  `T`-typed fields resolved to the type argument instead of `{}`.
- Tests: generator tests (`test/generator_test.dart`) run the builder on a
  sample controller; the `coerce` test now expects gisila's behaviour for
  an empty string (kept as `''`).

## 0.2.0 - MVC alignment with gisila 0.2.0 (BREAKING)

- **`config: RouteConfig?`** added to every HTTP-verb annotation
  (`@Get`, `@Post`, `@Put`, `@Patch`, `@Delete`, `@Head`,
  `@Options`). Re-exports gisila's `RouteConfig` and `UseRouteConfig`
  so consumers only need a single `import
  'package:gisila_doc/gisila_doc.dart';`.
- **Generated extension renamed** from `attachOpenApi(spec, router)`
  to `attachToApp(app, router, spec, {prefix})`. The new extension
  registers routes through `gisilaRoute(...)` so they go through the
  same MVC pipeline (per-route rate limit / timeout / content-type
  filter / AuthN+AuthZ / error mapping) as gisila core, *and*
  contributes operations / schemas / tags to the [OpenApiSpec].
- **Schema emitter learned about `Form` subclasses**: a parameter
  whose type is a gisila `Form` subtype now produces a request-body
  schema derived from the [FormField] hierarchy (`StringField` →
  `string`, `IntField` → `integer`, `EmailField` → `string +
  format:email`, `FileField` → `string + format:binary`, etc.).
- **`Form` and `Service` parameter binding**: the generator detects
  `Form` and `Service` subtypes and emits `await bindForm(...)` /
  `ctx.service<T>()` calls instead of going through the JSON body
  decoder.
- **gisila_doc now re-exports the gisila runtime** (`GisilaApp`,
  `AppConfig`, `RouteConfig`, `Service`, `Form`, `Authenticator`,
  `Principal`, `RequireAuth`/`Permissions`/`AnyPermission`/`Roles`,
  `gisilaRoute`, …) so a single `package:gisila_doc/gisila_doc.dart`
  import is enough. gisila's own `@Controller` / `@Get` / etc. are
  hidden to avoid name collisions with the doc-aware variants.

### Migration

1. Replace `attachOpenApi(spec, router)` call sites with
   `attachToApp(app, router, spec)` where `app` is your `GisilaApp`.
2. Boot your server through `GisilaApp.start(...)` instead of
   `io.serve(router.call, ...)`. The `GisilaApp` gives you the new
   MVC pipeline (error mapping, DB session middleware, …) without
   any extra work.
3. Register every `Service` subclass once at bootstrap with
   `app.registerService<T>(T.new)`.
4. Replace `fromJson` / handwritten body parsing with typed `Form`
   subclasses.

## 0.1.1

- Unified version with the rest of the gisila ecosystem (`gisila`, `gisila_orm`, `gisila_studio`).
- Updated `gisila` dependency constraint to `^0.1.1`.
- Bug fixes and stability improvements since the initial release.

## 0.1.0

- Initial release.
- Generate OpenAPI 3.1 specs from annotated Dart controllers.
- Shelf router wiring auto-generated via `build_runner`.
- Bundled Swagger UI served over Shelf.
- Minimal boilerplate with maximum type inference.
