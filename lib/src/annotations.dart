/// Annotations consumed by the build-time generator and used by the
/// runtime to enrich the OpenAPI document.
///
/// All annotations are deliberately small and free-standing so that user
/// code stays readable; the generator infers as much as it can from
/// parameter types and method signatures.
library gisila_doc.annotations;

import 'package:meta/meta_meta.dart';

/// Marks a class as an OpenAPI controller.
///
/// Every method annotated with one of [Get], [Post], [Put], [Patch],
/// [Delete], [Head], [Options] or the generic [Route] is registered as a
/// route on the shelf router and contributes an entry to the OpenAPI
/// document.
///
/// The optional [path] is prepended to every method-level route path. If
/// omitted, methods carry their full paths themselves.
///
/// [tags] are used as the default tag list for every operation in this
/// controller; methods can still add their own [Tag] annotations.
@Target({TargetKind.classType})
class Controller {
  const Controller([this.path = '', this.tags = const <String>[]]);

  /// Common prefix for every route in the controller, e.g. `/users`.
  final String path;

  /// Default OpenAPI tag(s) used to group this controller's operations.
  final List<String> tags;
}

/// Common base for HTTP-method annotations placed on controller methods.
///
/// The generator never instantiates [Route] directly; concrete subclasses
/// such as [Get] and [Post] carry the HTTP verb.
///
/// The optional [body] and [responses] parameters let you document the
/// request body schema and all response variants inline, without needing
/// separate [BodyDoc] / [Returns] / [Responses] annotations:
///
/// ```dart
/// @Post('/register',
///   summary: 'Register a new account',
///   body: BodyDoc(UserRegisterRequest, description: 'Registration payload'),
///   responses: [
///     Returns(statusCode: 201, bodyType: UserRegisterRequest),
///     Returns(statusCode: 400, bodyType: ErrorResponse),
///   ],
/// )
/// Future<Response> register(Request request) async { ... }
/// ```
@Target({TargetKind.method})
class Route {
  const Route(
    this.method,
    this.path, {
    this.summary,
    this.description,
    this.operationId,
    this.deprecated = false,
    this.tags = const <String>[],
    this.statusCode = 200,
    this.body,
    this.responses,
  });

  final String method;
  final String path;
  final String? summary;
  final String? description;
  final String? operationId;
  final bool deprecated;
  final List<String> tags;

  /// HTTP status code used for the successful response when the handler
  /// returns a value (rather than a [Response] directly). For `POST` the
  /// generator defaults this to `201` unless overridden.
  final int statusCode;

  /// Inline request-body documentation. Superseded by a standalone
  /// [BodyDoc] annotation on the same method if both are present.
  final BodyDoc? body;

  /// Inline response entries. The first element overrides the primary
  /// success response; the rest become additional response entries.
  /// Superseded by standalone [Returns] / [Responses] annotations if
  /// those are also present on the same method.
  final List<Returns>? responses;
}

class Get extends Route {
  const Get(
    String path, {
    String? summary,
    String? description,
    String? operationId,
    bool deprecated = false,
    List<String> tags = const <String>[],
    int statusCode = 200,
    BodyDoc? body,
    List<Returns>? responses,
  }) : super('GET', path,
            summary: summary,
            description: description,
            operationId: operationId,
            deprecated: deprecated,
            tags: tags,
            statusCode: statusCode,
            body: body,
            responses: responses);
}

class Post extends Route {
  const Post(
    String path, {
    String? summary,
    String? description,
    String? operationId,
    bool deprecated = false,
    List<String> tags = const <String>[],
    int statusCode = 201,
    BodyDoc? body,
    List<Returns>? responses,
  }) : super('POST', path,
            summary: summary,
            description: description,
            operationId: operationId,
            deprecated: deprecated,
            tags: tags,
            statusCode: statusCode,
            body: body,
            responses: responses);
}

class Put extends Route {
  const Put(
    String path, {
    String? summary,
    String? description,
    String? operationId,
    bool deprecated = false,
    List<String> tags = const <String>[],
    int statusCode = 200,
    BodyDoc? body,
    List<Returns>? responses,
  }) : super('PUT', path,
            summary: summary,
            description: description,
            operationId: operationId,
            deprecated: deprecated,
            tags: tags,
            statusCode: statusCode,
            body: body,
            responses: responses);
}

class Patch extends Route {
  const Patch(
    String path, {
    String? summary,
    String? description,
    String? operationId,
    bool deprecated = false,
    List<String> tags = const <String>[],
    int statusCode = 200,
    BodyDoc? body,
    List<Returns>? responses,
  }) : super('PATCH', path,
            summary: summary,
            description: description,
            operationId: operationId,
            deprecated: deprecated,
            tags: tags,
            statusCode: statusCode,
            body: body,
            responses: responses);
}

class Delete extends Route {
  const Delete(
    String path, {
    String? summary,
    String? description,
    String? operationId,
    bool deprecated = false,
    List<String> tags = const <String>[],
    int statusCode = 204,
    BodyDoc? body,
    List<Returns>? responses,
  }) : super('DELETE', path,
            summary: summary,
            description: description,
            operationId: operationId,
            deprecated: deprecated,
            tags: tags,
            statusCode: statusCode,
            body: body,
            responses: responses);
}

class Head extends Route {
  const Head(
    String path, {
    String? summary,
    String? description,
    String? operationId,
    bool deprecated = false,
    List<String> tags = const <String>[],
    List<Returns>? responses,
  }) : super('HEAD', path,
            summary: summary,
            description: description,
            operationId: operationId,
            deprecated: deprecated,
            tags: tags,
            responses: responses);
}

class Options extends Route {
  const Options(
    String path, {
    String? summary,
    String? description,
    String? operationId,
    bool deprecated = false,
    List<String> tags = const <String>[],
    List<Returns>? responses,
  }) : super('OPTIONS', path,
            summary: summary,
            description: description,
            operationId: operationId,
            deprecated: deprecated,
            tags: tags,
            responses: responses);
}

// ---------------------------------------------------------------------------
// Parameter / body annotations
// ---------------------------------------------------------------------------

/// Marks a method parameter as the request body. The body is decoded as
/// JSON and either passed as a `Map<String, dynamic>` or, if the
/// parameter type has a `fromJson` constructor, hydrated through that.
///
/// You usually do not need this annotation: a non-primitive parameter
/// that is not bound to a path placeholder is treated as the body by
/// default. Use it to override the content type or mark a body as
/// optional.
@Target({TargetKind.parameter})
class Body {
  const Body({
    this.contentType = 'application/json',
    this.required = true,
    this.description,
  });

  final String contentType;
  final bool required;
  final String? description;
}

/// Marks a method parameter as a query-string parameter. By default the
/// parameter name is used as the query key; pass [name] to override.
///
/// Optional/nullable Dart parameters become `required: false` in the
/// spec automatically.
@Target({TargetKind.parameter})
class Query {
  const Query({this.name, this.description, this.example});
  final String? name;
  final String? description;
  final Object? example;
}

/// Marks a method parameter as a path parameter. Inferred automatically
/// when the parameter name matches a `{placeholder}` segment in the
/// route path; use this to override naming.
@Target({TargetKind.parameter})
class Path {
  const Path({this.name, this.description, this.example});
  final String? name;
  final String? description;
  final Object? example;
}

/// Marks a method parameter as an HTTP header.
@Target({TargetKind.parameter})
class Header {
  const Header({this.name, this.description});
  final String? name;
  final String? description;
}

// ---------------------------------------------------------------------------
// Response / metadata annotations
// ---------------------------------------------------------------------------

/// Documents an additional response entry on a route. Multiple
/// annotations can be stacked to describe error and success cases.
///
/// ```dart
/// @Get('/{id}')
/// @ApiResponse(404, description: 'User not found')
/// @ApiResponse(200, bodyType: UserResponse, description: 'Found')
/// Future<Response> getUser(String id, Request request) async => ...;
/// ```
@Target({TargetKind.method})
class ApiResponse {
  const ApiResponse(
    this.statusCode, {
    this.description,
    this.contentType = 'application/json',
    this.bodyType,
  });
  final int statusCode;
  final String? description;
  final String contentType;

  /// Optional Dart type for the response body schema at this status code.
  final Type? bodyType;
}

/// Overrides the inferred success status code and description on a
/// route. The body type is taken from the method's return type unless
/// [bodyType] is supplied, which is useful when the method returns a
/// raw `Response` but you still want the OpenAPI document to describe
/// the response body schema.
///
/// ```dart
/// @Get('/me')
/// @Returns(bodyType: UserResponse)
/// Future<Response> me(Request request) async { ... }
/// ```
@Target({TargetKind.method})
class Returns {
  const Returns({
    this.statusCode,
    this.description,
    this.contentType = 'application/json',
    this.bodyType,
  });
  final int? statusCode;
  final String? description;
  final String contentType;

  /// The Dart type to use as the response body schema. When the method
  /// returns `Future<Response>` directly, the generator cannot infer the
  /// body shape; supply this to document it explicitly.
  final Type? bodyType;
}

/// Documents a query parameter for a route whose handler reads from
/// `request.url.queryParameters` directly (raw `Request` pattern).
///
/// Stack one annotation per parameter:
///
/// ```dart
/// @Get('/products')
/// @QueryDoc('offset', type: int)
/// @QueryDoc('limit', type: int)
/// @QueryDoc('search')
/// Future<Response> listProducts(Request request) async { ... }
/// ```
///
/// [type] defaults to `String`. Pass `required: true` when the endpoint
/// rejects requests that omit the parameter.
@Target({TargetKind.method})
class QueryDoc {
  const QueryDoc(
    this.name, {
    this.type = String,
    this.required = false,
    this.description,
  });

  final String name;

  /// Dart type used to derive the OpenAPI schema (`String`, `int`,
  /// `double`, `bool`, `DateTime`, …).
  final Type type;
  final bool required;
  final String? description;
}

/// Describes the JSON request body schema for a route.
///
/// Preferred usage — pass it inline via the route annotation's `body:`
/// parameter so everything stays in one place:
///
/// ```dart
/// @Post('/login',
///   body: BodyDoc(LoginRequest, description: 'Login credentials'),
/// )
/// Future<Response> login(Request request) async { ... }
/// ```
///
/// It can also be used as a standalone method annotation when the inline
/// style is inconvenient (e.g. a shared mixin), but that pattern is
/// considered legacy:
///
/// ```dart
/// @Post('/login')
/// @BodyDoc(LoginRequest)   // legacy — prefer the inline body: param above
/// Future<Response> login(Request request) async { ... }
/// ```
///
/// The [type] must be a class whose constructor parameters (or instance
/// fields) the schema emitter can introspect.
@Target({TargetKind.method})
class BodyDoc {
  const BodyDoc(
    this.type, {
    this.required = true,
    this.description,
    this.contentType = 'application/json',
  });

  /// The Dart class that describes the request body shape.
  final Type type;
  final bool required;
  final String? description;
  final String contentType;
}

/// Declares multiple response entries for a route in a single annotation,
/// as an alternative to the inline `responses:` parameter on the route
/// annotation. Prefer the inline style:
///
/// ```dart
/// @Post('/register',
///   responses: [
///     Returns(statusCode: 201, bodyType: UserRegisterRequest),
///     Returns(statusCode: 400, bodyType: ErrorResponse),
///   ],
/// )
/// ```
///
/// Use this standalone annotation only when you need to apply the same
/// response set to multiple routes via a mixin or when the inline
/// `responses:` list would be inconveniently long.
///
/// The first entry is treated as the primary success response (overriding
/// the route's default status code / description / body type); every
/// subsequent entry is added as an additional response entry.
@Target({TargetKind.method})
class Responses {
  const Responses(this.responses);

  /// Ordered list of response entries. The first element overrides the
  /// primary success response; the rest become additional response entries.
  final List<Returns> responses;
}

/// Adds extra OpenAPI tag(s) to a single operation.
@Target({TargetKind.method})
class Tag {
  const Tag(this.name, [this.description]);
  final String name;
  final String? description;
}
