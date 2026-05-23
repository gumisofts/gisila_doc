/// Small analyzer / string helpers shared by the build-time code.
library gisila_doc.builder.utils;

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

/// Returns the display string of [type] without any nullability
/// suffix.
String typeDisplayName(DartType type) {
  final full = type.getDisplayString();
  return full.endsWith('?') ? full.substring(0, full.length - 1) : full;
}

/// Returns the display string of [type] including its nullability
/// suffix (e.g. `int?`). Used when we need to round-trip the exact
/// Dart type into generated source.
String typeDisplayNameNullable(DartType type) => type.getDisplayString();

/// True iff [type] is `T?` (or `Null`).
bool isNullable(DartType type) =>
    type.nullabilitySuffix == NullabilitySuffix.question || type.isDartCoreNull;

/// True iff [type] is one of the standard "primitive" shelf-friendly
/// types we can coerce from a path/query string.
bool isCoercible(DartType type) {
  final name = typeDisplayName(type);
  return const {
    'String',
    'int',
    'double',
    'num',
    'bool',
    'DateTime',
  }.contains(name);
}

/// True iff [type] is `shelf.Request` from `package:shelf/shelf.dart`.
bool isShelfRequest(DartType type) {
  final element = type.element;
  if (element is! ClassElement) return false;
  return element.name == 'Request' &&
      element.library.identifier.startsWith('package:shelf/');
}

/// True iff [type] is `shelf.Response` from `package:shelf/shelf.dart`.
bool isShelfResponse(DartType type) {
  final element = type.element;
  if (element is! ClassElement) return false;
  return element.name == 'Response' &&
      element.library.identifier.startsWith('package:shelf/');
}

/// Unwraps `Future<T>` into `T`, returning [type] unchanged otherwise.
DartType unwrapFuture(DartType type) {
  if (type is InterfaceType &&
      type.element.name == 'Future' &&
      type.element.library.isDartAsync) {
    if (type.typeArguments.isNotEmpty) return type.typeArguments.first;
  }
  return type;
}

/// True iff [type] is `void` or `Future<void>`.
bool isVoid(DartType type) {
  final unwrapped = unwrapFuture(type);
  return unwrapped is VoidType;
}

/// Returns `true` if [type] is a `List<X>` (any X).
bool isList(DartType type) => type is InterfaceType && type.isDartCoreList;

/// Returns `true` if [type] is a `Map<String, X>`.
bool isStringMap(DartType type) {
  if (type is! InterfaceType || !type.isDartCoreMap) return false;
  if (type.typeArguments.length != 2) return false;
  return typeDisplayName(type.typeArguments[0]) == 'String';
}

/// Returns the inner T of `List<T>` or `null` if [type] is not a list.
DartType? listElementType(DartType type) {
  if (type is InterfaceType &&
      type.isDartCoreList &&
      type.typeArguments.isNotEmpty) {
    return type.typeArguments.first;
  }
  return null;
}

/// Returns the value type V of `Map<String, V>` or `null` if [type] is
/// not such a map.
DartType? mapValueType(DartType type) {
  if (type is InterfaceType &&
      type.isDartCoreMap &&
      type.typeArguments.length == 2) {
    return type.typeArguments[1];
  }
  return null;
}

/// Extracts all path placeholders (e.g. `{id}`) from [path] preserving
/// the order they appear. Returns the placeholder names without braces.
Iterable<String> pathPlaceholders(String path) sync* {
  final re = RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}');
  for (final m in re.allMatches(path)) {
    yield m.group(1)!;
  }
}

/// Converts an OpenAPI-style path like `/users/{id}` to a
/// shelf_router-style path like `/users/<id>`.
String toShelfPath(String path) {
  return path.replaceAllMapped(
    RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}'),
    (m) => '<${m.group(1)}>',
  );
}

/// Returns the unnamed (default) constructor of [cls] or `null`.
ConstructorElement? defaultConstructor(ClassElement cls) {
  for (final c in cls.constructors) {
    if (c.name.isEmpty && !c.isFactory) return c;
  }
  // Some classes only expose a factory as their default.
  for (final c in cls.constructors) {
    if (c.name.isEmpty) return c;
  }
  return null;
}

/// Returns the `fromJson(Map<String, dynamic>)` factory if [cls]
/// exposes one. Used to decode request bodies.
ConstructorElement? fromJsonConstructor(ClassElement cls) {
  for (final c in cls.constructors) {
    if (c.name != 'fromJson') continue;
    if (c.parameters.length != 1) continue;
    final p = c.parameters.first;
    final t = p.type;
    if (t is InterfaceType && t.isDartCoreMap) return c;
  }
  return null;
}

/// Returns the `toJson()` method if [cls] exposes one returning `Map`.
MethodElement? toJsonMethod(ClassElement cls) {
  for (final m in cls.methods) {
    if (m.name != 'toJson') continue;
    if (m.parameters.isNotEmpty) continue;
    return m;
  }
  return null;
}

/// Quotes [value] as a Dart single-quoted string literal.
String dartString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll(r"'", r"\'")
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\$', r'\$');
  return "'$escaped'";
}
