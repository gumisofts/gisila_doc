# shelf_openapi

> Generate **OpenAPI 3.1** specs and **shelf_router** wiring from annotated
> Dart controllers - with the smallest possible amount of boilerplate.

```dart
@Controller('/users', ['Users'])
class UsersController {
  @Get('/{id}', summary: 'Fetch a user')
  Future<User> getUser(String id) async => repo.find(id);

  @Post('/', summary: 'Create a user')
  Future<User> createUser(CreateUser body) async => repo.create(body);
}
```

```dart
final spec = OpenApiSpec(info: ApiInfo(title: 'Demo', version: '1.0.0'));
final router = Router();

UsersController().attachOpenApi(spec, router);
router.mount('/', docsHandler(spec));   // /openapi.json, /docs, /redoc

await io.serve(router.call, '0.0.0.0', 8080);
```

That's the entire integration. The path parameter, the request body schema,
the response schema, the status codes, and the Swagger UI are all derived
automatically.

---

## What's in the box

* `@Controller` / `@Get` / `@Post` / `@Put` / `@Patch` / `@Delete` /
  `@Head` / `@Options` annotations.
* `@Path` / `@Query` / `@Header` / `@Body` parameter annotations - usually
  **not needed** because the generator infers the location from the
  parameter name and type.
* `@Returns` / `@ApiResponse` / `@Tag` for fine-grained metadata.
* Build-time JSON-Schema generation from your Dart classes. Constructor
  parameters drive `required`; nullable types drive optionality.
* A runtime `OpenApiSpec` you can extend programmatically.
* A bundled `docsHandler` that serves the spec, Swagger UI (CDN-loaded),
  and ReDoc out of the box.

## Install

In your application's `pubspec.yaml`:

```yaml
dependencies:
  shelf: ^1.4.1
  shelf_router: ^1.1.4
  shelf_openapi:
    path: ../shelf_openapi   # or path / git / pub later
dev_dependencies:
  build_runner: ^2.5.0
```

## Authoring a controller

```dart
import 'package:shelf/shelf.dart';
import 'package:shelf_openapi/shelf_openapi.dart';
import 'package:shelf_router/shelf_router.dart';

import '../models/user.dart';

part 'users_controller.g.dart';   // <-- required, generated below

@Controller('/users', ['Users'])
class UsersController {
  /// Returns every user, optionally paginated.
  @Get('/', summary: 'List users')
  Future<List<User>> listUsers({int? limit, int? offset}) async => ...;

  @Get('/{id}', summary: 'Fetch a user', operationId: 'getUserById')
  @ApiResponse(404, description: 'User not found')
  Future<Response> getUser(String id) async => ...;   // shelf-style is OK too

  @Post('/', summary: 'Create a user')
  Future<User> createUser(CreateUser body) async => ...;

  @Delete('/{id}', summary: 'Delete a user')
  Future<void> deleteUser(String id) async => ...;
}
```

Run:

```bash
dart run build_runner build --delete-conflicting-outputs
```

That creates `users_controller.g.dart` with an extension method
`attachOpenApi(OpenApiSpec spec, Router router, {String prefix = ''})` on
your controller.

## Parameter inference rules

The generator picks a source for each parameter using these rules, in
order:

1. An explicit annotation: `@Path`, `@Query`, `@Header`, `@Body`.
2. A parameter named like a `{placeholder}` in the route path is a
   **path** parameter (`@Get('/users/{id}')` + `String id`).
3. A primitive parameter (`int`, `String`, `double`, `bool`, `DateTime`,
   `num`) is a **query** parameter.
4. A `shelf.Request` parameter is passed through untouched.
5. Anything else is the **request body**. At most one body parameter
   per method - the generator decodes it as JSON, calling the type's
   `fromJson(Map<String, dynamic>)` factory if it exists.

Nullable types (`int?`, `String?`) become `required: false` in the
spec automatically.

## Response handling

* Methods returning `Response` / `Future<Response>` are passed through
  untouched (shelf style).
* Methods returning `void` / `Future<void>` send an empty response with
  the declared status code (`204 No Content` by default for `@Delete`).
* Methods returning any other type are JSON-encoded; the type's
  `toJson()` method is called automatically (also recursively for
  `List<T>` / `Map<String, V>`).

## JSON Schema inference

Each Dart class referenced as a body, return type, or parameter is
walked through its default constructor and emitted as a component
schema under `#/components/schemas/{ClassName}`. Nullable / optional
parameters become non-required properties.

Built-in coverage:

| Dart                    | OpenAPI                                       |
|-------------------------|-----------------------------------------------|
| `String`                | `{type: string}`                              |
| `int`                   | `{type: integer, format: int64}`              |
| `double` / `num`        | `{type: number, format: double}`              |
| `bool`                  | `{type: boolean}`                             |
| `DateTime`              | `{type: string, format: date-time}`           |
| `Uri`                   | `{type: string, format: uri}`                 |
| `List<T>`               | `{type: array, items: <T>}`                   |
| `Map<String, V>`        | `{type: object, additionalProperties: <V>}`   |
| custom class            | `{ $ref: '#/components/schemas/MyClass' }`    |
| `T?`                    | union with `'null'` (OpenAPI 3.1 style)       |

## Errors

`coerce` and `readJsonBody` throw `BadRequestException` when the input
is malformed; the generated wrapper catches it and returns a `400` with
a small JSON error envelope. `TypeError` and `FormatException`
(typically raised inside a hand-written `fromJson`) are also turned
into `400` responses so a malformed payload never escapes as `500`.

## Bundled docs UI

`docsHandler(spec)` mounts:

* `GET /openapi.json` - the rendered document.
* `GET /docs` - Swagger UI (loaded from `unpkg.com`).
* `GET /redoc` - ReDoc (loaded from `cdn.redoc.ly`).

If you want to serve from an offline asset bundle instead, the
`OpenApiSpec.toMap()` / `OpenApiSpec.toJson()` getters are all you need.

## Example

A working end-to-end demo lives in [`example/`](./example):

```bash
cd example
dart pub get
dart run build_runner build --delete-conflicting-outputs
dart run bin/server.dart
# open http://localhost:8080/docs
```

## Version compatibility

The generator is intentionally pinned to the legacy `analyzer` element
API (`ClassElement` / `ParameterElement` / `.parameters`) which is
preserved in `analyzer 7.x`. We will follow up with an `analyzer 8+`
build of the generator once source_gen-compatible upstream packages
stabilise on the `Element2` API.
