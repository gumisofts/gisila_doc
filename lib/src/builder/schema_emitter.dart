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
        return nullable ? '<String, Object?>{}' : '<String, Object?>{}';
    }

    // List<T>, Set<T>, Iterable<T> -----------------------------------
    final listInner = iterableElementType(type);
    if (listInner != null) {
      final inner = _emit(listInner);
      final typeExpr = nullable ? "<Object?>['array', 'null']" : "'array'";
      final unique =
          (type as InterfaceType).isDartCoreSet ? ", 'uniqueItems': true" : '';
      return "<String, Object?>{'type': $typeExpr, 'items': $inner$unique}";
    }

    // Map<String, V> -------------------------------------------------
    final mapVal = mapValueType(type);
    if (mapVal != null) {
      final inner = _emit(mapVal);
      final typeExpr = nullable ? "<Object?>['object', 'null']" : "'object'";
      return "<String, Object?>{'type': $typeExpr, "
          "'additionalProperties': $inner}";
    }

    // Enum: sent as its name unless it defines its own toJson().
    if (type is InterfaceType && type.element is EnumElement) {
      final element = type.element as EnumElement;
      if (element.getMethod('toJson') != null) return '<String, Object?>{}';
      final names = [
        for (final f in element.fields)
          if (f.isEnumConstant) dartString(f.name),
      ];
      final typeExpr = nullable ? "<Object?>['string', 'null']" : "'string'";
      final values = [...names, if (nullable) 'null'];
      return "<String, Object?>{'type': $typeExpr, "
          "'enum': <Object?>[${values.join(', ')}]}";
    }

    // User-defined class --------------------------------------------
    if (type is InterfaceType) {
      final element = type.element;
      if (element is ClassElement && !element.library.isInSdk) {
        final componentName = _componentName(type);
        // Form subclass: introspect FormField members.
        if (isFormSubtype(type)) {
          _registerFormSchema(componentName, element);
        } else {
          _registerClassSchema(componentName, type);
        }
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

  /// The `components.schemas` name for [type]. Generic instantiations get
  /// their type arguments in the name (`Page<User>` → `Page_User`,
  /// `Page<List<Post?>>` → `Page_List_PostNullable`), so each one is its own
  /// schema instead of all sharing `Page`.
  String _componentName(InterfaceType type) {
    if (type.typeArguments.isEmpty) return type.element.name;
    final display = type
        .getDisplayString()
        .replaceFirst(RegExp(r'\?$'), '')
        .replaceAll('?', 'Nullable');
    return display
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String _primitive(String type, {bool nullable = false, String? format}) {
    final typeExpr = nullable ? "<Object?>['$type', 'null']" : "'$type'";
    final fmt = format == null ? '' : ", 'format': '$format'";
    return "<String, Object?>{'type': $typeExpr$fmt}";
  }

  /// Registers a JSON schema for a gisila `Form` subclass.
  ///
  /// Walks every instance field on [element] whose type is a
  /// [FormField] subtype, picks the schema fragment for the field's
  /// type parameter (`StringField` → `string`, `IntField` → `integer`,
  /// `EmailField` → `string + format:email`, `FileField` → `string +
  /// format:binary`, …), and builds an `object` schema with the
  /// Dart field name as the property key.
  ///
  /// We can't currently read the `required:` flag from each field's
  /// initializer (FormField is not `const`), so every property is
  /// emitted as optional - the runtime [Form.bind] still enforces it.
  void _registerFormSchema(String name, ClassElement element) {
    if (componentSchemas.containsKey(name)) return;
    componentSchemas[name] = "<String, Object?>{}";

    final propertyEntries = <String>[];
    for (final field in _allInstanceFields(element)) {
      if (field.isStatic || field.isSynthetic) continue;
      if (!isFormFieldSubtype(field.type)) continue;
      final propertyName = field.name;
      final schema = _formFieldSchemaFor(field.type);
      propertyEntries.add("'$propertyName': $schema");
    }
    componentSchemas[name] = "<String, Object?>{"
        "'type': 'object', "
        "'properties': <String, Object?>{${propertyEntries.join(', ')}}"
        '}';
  }

  /// Walks the class hierarchy and yields every instance field, with
  /// most-derived first. Used by the Form schema emitter so subclass
  /// fields don't shadow base-class ones in the spec.
  Iterable<FieldElement> _allInstanceFields(ClassElement element) sync* {
    ClassElement? cursor = element;
    final seen = <String>{};
    while (cursor != null && !cursor.library.isInSdk) {
      for (final f in cursor.fields) {
        if (seen.add(f.name)) yield f;
      }
      final superType = cursor.supertype;
      if (superType == null) break;
      final superElement = superType.element;
      cursor = superElement is ClassElement ? superElement : null;
    }
  }

  /// Picks the JSON schema fragment for a [FormField] instance based
  /// on the concrete subclass.
  String _formFieldSchemaFor(DartType type) {
    final name = typeDisplayName(type);
    switch (name) {
      case 'StringField':
        return "<String, Object?>{'type': 'string'}";
      case 'EmailField':
        return "<String, Object?>{'type': 'string', 'format': 'email'}";
      case 'PasswordField':
        return "<String, Object?>{'type': 'string', 'format': 'password'}";
      case 'IntField':
        return "<String, Object?>{'type': 'integer', 'format': 'int64'}";
      case 'DoubleField':
        return "<String, Object?>{'type': 'number', 'format': 'double'}";
      case 'BoolField':
        return "<String, Object?>{'type': 'boolean'}";
      case 'DateTimeField':
        return "<String, Object?>{'type': 'string', 'format': 'date-time'}";
      case 'FileField':
        return "<String, Object?>{'type': 'string', 'format': 'binary'}";
      case 'JsonField':
        return "<String, Object?>{'type': 'object'}";
    }
    // Generic FormField<T> - try to recover T.
    if (type is InterfaceType && type.typeArguments.isNotEmpty) {
      return _emit(type.typeArguments.first);
    }
    return "<String, Object?>{}";
  }

  /// Reads fields through [type] rather than its class, so a generic
  /// class's `T` fields carry the instantiation's type arguments.
  void _registerClassSchema(String name, InterfaceType type) {
    if (componentSchemas.containsKey(name)) return;
    // Reserve the name early so circular references resolve to a $ref
    // rather than recursing forever.
    componentSchemas[name] = "<String, Object?>{}";

    final element = type.element as ClassElement;
    final ctor = defaultConstructorOf(type);
    final fields = <_FieldShape>[];

    if (ctor != null && ctor.parameters.isNotEmpty) {
      // Use constructor params as the authoritative field set. This
      // matches what fromJson/toJson typically expose and skips private
      // / derived fields that the user doesn't want in their schema.
      for (final p in ctor.parameters) {
        final fieldName = p.name;
        final required = p.isRequiredNamed ||
            p.isRequiredPositional ||
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
        final fieldType = type.getGetter(f.name)?.returnType ?? f.type;
        fields.add(_FieldShape(
          name: f.name,
          type: fieldType,
          required: !isNullable(fieldType),
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
