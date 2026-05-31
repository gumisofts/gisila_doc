# Changelog

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
