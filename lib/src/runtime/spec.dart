/// Runtime model of an OpenAPI 3.1.0 document.
///
/// The shape mirrors the spec closely but only carries the fields the
/// generator emits. Unknown / advanced fields can be merged in via
/// [OpenApiSpec.extra].
library gisila_doc.runtime.spec;

import 'dart:convert';

/// Top-level OpenAPI document.
///
/// Built up by the generated `register*` functions and serialized on
/// demand via [toMap] / [toJson].
class OpenApiSpec {
  OpenApiSpec({
    required this.info,
    this.servers = const <ApiServer>[],
    this.openapi = '3.1.0',
    Map<String, Object?>? extra,
  }) : extra = extra ?? <String, Object?>{};

  final String openapi;
  final ApiInfo info;
  final List<ApiServer> servers;

  /// Path → method → operation. Insertion order is preserved so the
  /// emitted document is stable across runs.
  final Map<String, Map<String, Operation>> paths =
      <String, Map<String, Operation>>{};

  /// Schemas accumulated through [putSchema], keyed by component name.
  final Map<String, Map<String, Object?>> _schemas =
      <String, Map<String, Object?>>{};

  /// Top-level tag metadata.
  final Map<String, _TagDef> _tags = <String, _TagDef>{};

  /// Arbitrary extra fields merged into the emitted document.
  final Map<String, Object?> extra;

  /// Adds/overrides an operation at [path] / [method].
  void putOperation(String path, String method, Operation op) {
    final byMethod =
        paths.putIfAbsent(path, () => <String, Operation>{});
    byMethod[method.toLowerCase()] = op;
  }

  /// Registers a JSON schema under [name] in `components.schemas`.
  ///
  /// If a schema with the same name is already registered the call is a
  /// no-op (we trust the first registration to win; the generator emits
  /// each schema only once per type but a runtime may call us multiple
  /// times via multiple controllers).
  void putSchema(String name, Map<String, Object?> schema) {
    _schemas.putIfAbsent(name, () => schema);
  }

  /// Whether [name] has already been registered.
  bool hasSchema(String name) => _schemas.containsKey(name);

  /// Adds (or merges) a tag description.
  void putTag(String name, {String? description}) {
    final existing = _tags[name];
    if (existing == null) {
      _tags[name] = _TagDef(name: name, description: description);
    } else if (description != null && existing.description == null) {
      _tags[name] = _TagDef(name: name, description: description);
    }
  }

  /// Serializes the document to a plain map.
  Map<String, Object?> toMap() {
    final out = <String, Object?>{
      'openapi': openapi,
      'info': info.toMap(),
      if (servers.isNotEmpty)
        'servers': servers.map((s) => s.toMap()).toList(growable: false),
      if (_tags.isNotEmpty)
        'tags': _tags.values.map((t) => t.toMap()).toList(growable: false),
      'paths': <String, Object?>{
        for (final entry in paths.entries)
          entry.key: <String, Object?>{
            for (final op in entry.value.entries) op.key: op.value.toMap(),
          },
      },
      if (_schemas.isNotEmpty)
        'components': <String, Object?>{
          'schemas': _schemas,
        },
    };
    if (extra.isNotEmpty) out.addAll(extra);
    return out;
  }

  String toJson({bool pretty = true}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(toMap());
  }
}

class ApiInfo {
  const ApiInfo({
    required this.title,
    required this.version,
    this.description,
    this.termsOfService,
    this.contact,
    this.license,
  });
  final String title;
  final String version;
  final String? description;
  final String? termsOfService;
  final Contact? contact;
  final License? license;

  Map<String, Object?> toMap() => <String, Object?>{
        'title': title,
        'version': version,
        if (description != null) 'description': description,
        if (termsOfService != null) 'termsOfService': termsOfService,
        if (contact != null) 'contact': contact!.toMap(),
        if (license != null) 'license': license!.toMap(),
      };
}

class Contact {
  const Contact({this.name, this.url, this.email});
  final String? name;
  final String? url;
  final String? email;
  Map<String, Object?> toMap() => <String, Object?>{
        if (name != null) 'name': name,
        if (url != null) 'url': url,
        if (email != null) 'email': email,
      };
}

class License {
  const License({required this.name, this.identifier, this.url});
  final String name;
  final String? identifier;
  final String? url;
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        if (identifier != null) 'identifier': identifier,
        if (url != null) 'url': url,
      };
}

class ApiServer {
  const ApiServer({required this.url, this.description});
  final String url;
  final String? description;
  Map<String, Object?> toMap() => <String, Object?>{
        'url': url,
        if (description != null) 'description': description,
      };
}

/// A single HTTP operation. The generator constructs these inline.
class Operation {
  Operation({
    this.summary,
    this.description,
    this.operationId,
    this.deprecated = false,
    this.tags = const <String>[],
    this.parameters = const <Parameter>[],
    this.requestBody,
    this.responses = const <String, ResponseSpec>{},
  });

  final String? summary;
  final String? description;
  final String? operationId;
  final bool deprecated;
  final List<String> tags;
  final List<Parameter> parameters;
  final RequestBody? requestBody;
  final Map<String, ResponseSpec> responses;

  Map<String, Object?> toMap() => <String, Object?>{
        if (tags.isNotEmpty) 'tags': tags,
        if (summary != null) 'summary': summary,
        if (description != null) 'description': description,
        if (operationId != null) 'operationId': operationId,
        if (deprecated) 'deprecated': true,
        if (parameters.isNotEmpty)
          'parameters':
              parameters.map((p) => p.toMap()).toList(growable: false),
        if (requestBody != null) 'requestBody': requestBody!.toMap(),
        'responses': <String, Object?>{
          for (final entry in responses.entries)
            entry.key.toString(): entry.value.toMap(),
        },
      };
}

class Parameter {
  const Parameter({
    required this.name,
    required this.location,
    required this.schema,
    this.required = false,
    this.description,
    this.example,
  });

  /// `query`, `path`, `header`, or `cookie`.
  final String location;
  final String name;
  final Map<String, Object?> schema;
  final bool required;
  final String? description;
  final Object? example;

  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'in': location,
        if (description != null) 'description': description,
        'required': required,
        'schema': schema,
        if (example != null) 'example': example,
      };
}

class RequestBody {
  const RequestBody({
    required this.content,
    this.required = true,
    this.description,
  });
  final Map<String, MediaType> content;
  final bool required;
  final String? description;

  Map<String, Object?> toMap() => <String, Object?>{
        if (description != null) 'description': description,
        'required': required,
        'content': <String, Object?>{
          for (final entry in content.entries) entry.key: entry.value.toMap(),
        },
      };
}

class ResponseSpec {
  const ResponseSpec({required this.description, this.content});
  final String description;
  final Map<String, MediaType>? content;

  Map<String, Object?> toMap() => <String, Object?>{
        'description': description,
        if (content != null && content!.isNotEmpty)
          'content': <String, Object?>{
            for (final entry in content!.entries)
              entry.key: entry.value.toMap(),
          },
      };
}

class MediaType {
  const MediaType({required this.schema, this.example});
  final Map<String, Object?> schema;
  final Object? example;
  Map<String, Object?> toMap() => <String, Object?>{
        'schema': schema,
        if (example != null) 'example': example,
      };
}

class _TagDef {
  const _TagDef({required this.name, this.description});
  final String name;
  final String? description;
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        if (description != null) 'description': description,
      };
}
