/// Converts Dart types to JSON Schema fragments at build-time.
///
/// The emitter produces two artefacts:
///
/// 1. A Dart **expression** (returned by [emitInline]) that, when
///    evaluated at runtime, yields a `Map<String, Object?>` describing
///    the schema. Use this for parameters and request/response bodies.
///
/// 2. A set of **side-effect statements** (collected in [extraRegistrations])
///    that register reusable component schemas on the shared
///    `OpenApiSpec`. Custom user classes are emitted by reference
///    (`{r'\$ref': '#/components/schemas/Foo'}`) so they appear once in
///    `components.schemas` and the rest of the document stays compact.
library gisila_doc.builder.schema_emitter;

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import 'utils.dart';

class SchemaEmitter {
  SchemaEmitter();

  /// Names of component schemas that need a `spec.putSchema(...)` call
  /// before the operation is registered. Map: component name → Dart
  /// expression that builds the schema map.
  final Map<String, String> componentSchemas = <String, String>{};

  /// Returns a Dart expression for the inline JSON Schema of [type].
  String emitInline(DartType type) {
    return _emit(type);
  }

  String _emit(DartType type) {
    final nullable = isNullable(type);
    final name = typeDisplayName(type);

    // Primitives -----------------------------------------------------
    switch (name) {
      case 'String':
        return _primitive('string', nullable: nullable);
      case 'int':
        return _primitive('integer', nullable: nullable, format: 'int64');
      case 'double':
        return _primitive('number', nullable: nullable, format: 'double');
      case 'num':
        return _primitive('number', nullable: nullable);
      case 'bool':
        return _primitive('boolean', nullable: nullable);
      case 'DateTime':
        return _primitive('string', nullable: nullable, format: 'date-time');
      case 'Uri':
        return _primitive('string', nullable: nullable, format: 'uri');
      case 'dynamic':
      case 'Object':
        return nullable
            ? '<String, Object?>{}'
            : '<String, Object?>{}';
    }

    // List<T> --------------------------------------------------------
    final listInner = listElementType(type);
    if (listInner != null) {
      final inner = _emit(listInner);
      final typeExpr = nullable
          ? "<Object?>['array', 'null']"
          : "'array'";
      return "<String, Object?>{'type': $typeExpr, 'items': $inner}";
    }

    // Map<String, V> -------------------------------------------------
    final mapVal = mapValueType(type);
    if (mapVal != null) {
      final inner = _emit(mapVal);
      final typeExpr = nullable
          ? "<Object?>['object', 'null']"
          : "'object'";
      return "<String, Object?>{'type': $typeExpr, "
          "'additionalProperties': $inner}";
    }

    // User-defined class --------------------------------------------
    if (type is InterfaceType) {
      final element = type.element;
      if (element is ClassElement && !element.library.isInSdk) {
        final componentName = element.name;
        _registerClassSchema(componentName, element);
        // r'$ref' is a raw string literal that prints as the literal
        // `$ref` JSON key (no interpolation). We could also use
        // `'\$ref'` but the raw form is clearer in generated code.
        final ref =
            "<String, Object?>{r'\$ref': '#/components/schemas/$componentName'}";
        if (nullable) {
          // OpenAPI 3.1 allows null via union; wrap with anyOf.
          return "<String, Object?>{'anyOf': <Object?>[$ref, "
              "<String, Object?>{'type': 'null'}]}";
        }
        return ref;
      }
    }

    // Fallback: untyped object.
    return "<String, Object?>{}";
  }

  String _primitive(String type, {bool nullable = false, String? format}) {
    final typeExpr = nullable
        ? "<Object?>['$type', 'null']"
        : "'$type'";
    final fmt = format == null ? '' : ", 'format': '$format'";
    return "<String, Object?>{'type': $typeExpr$fmt}";
  }

  void _registerClassSchema(String name, ClassElement element) {
    if (componentSchemas.containsKey(name)) return;
    // Reserve the name early so circular references resolve to a $ref
    // rather than recursing forever.
    componentSchemas[name] = "<String, Object?>{}";

    final ctor = defaultConstructor(element);
    final fields = <_FieldShape>[];

    if (ctor != null && ctor.parameters.isNotEmpty) {
      // Use constructor params as the authoritative field set. This
      // matches what fromJson/toJson typically expose and skips private
      // / derived fields that the user doesn't want in their schema.
      for (final p in ctor.parameters) {
        final fieldName = p.name;
        final required = p.isRequiredNamed || p.isRequiredPositional ||
            (!p.isOptional && !isNullable(p.type));
        fields.add(_FieldShape(
          name: fieldName,
          type: p.type,
          required: required && !isNullable(p.type),
        ));
      }
    } else {
      // Fall back to walking instance fields.
      for (final f in element.fields) {
        if (f.isStatic || f.isSynthetic) continue;
        fields.add(_FieldShape(
          name: f.name,
          type: f.type,
          required: !isNullable(f.type),
        ));
      }
    }

    final propertyEntries = <String>[];
    final requiredEntries = <String>[];
    for (final f in fields) {
      final propSchema = _emit(f.type);
      propertyEntries.add("'${f.name}': $propSchema");
      if (f.required) {
        requiredEntries.add("'${f.name}'");
      }
    }

    final required = requiredEntries.isEmpty
        ? ''
        : ", 'required': <String>[${requiredEntries.join(', ')}]";

    componentSchemas[name] = "<String, Object?>{"
        "'type': 'object', "
        "'properties': <String, Object?>{${propertyEntries.join(', ')}}"
        '$required'
        '}';
  }
}

class _FieldShape {
  _FieldShape({required this.name, required this.type, required this.required});
  final String name;
  final DartType type;
  final bool required;
}
