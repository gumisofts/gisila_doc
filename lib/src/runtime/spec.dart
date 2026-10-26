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
    Map<String, SecurityScheme>? securitySchemes,
    Map<String, Object?>? extra,
  })  : securitySchemes =
            securitySchemes ?? const {'bearerAuth': SecurityScheme.bearer()},
        extra = extra ?? <String, Object?>{};

  final String openapi;
  final ApiInfo info;
  final List<ApiServer> servers;

  /// How guarded operations authenticate, emitted under
  /// `components.securitySchemes`. Every operation with
  /// [Operation.requiresAuth] lists each scheme as an alternative. Defaults
  /// to a single HTTP bearer scheme (`Authorization: Bearer <token>`), which
  /// is what gisila's authenticators read; pass `{}` to leave security out
  /// of the document.
  final Map<String, SecurityScheme> securitySchemes;

  /// Path → method → operation. Insertion order is preserved so the
  /// emitted document is stable across runs.
  final Map<String, Map<String, Operation>> paths =
      <String, Map<String, Operation>>{};

  /// Schemas accumulated through [putSchema], keyed by component name.
  final Map<String, Map<String, Object?>> _schemas =
      <String, Map<String, Object?>>{};

  /// Top-level tag metadata.
  final Map<String, _TagDef> _tags = <String, _TagDef>{};

  /// Arbitrary extra fields merged into the emitted document. Top-level
  /// keys replace generated ones, except `components`, which is merged
  /// section by section (an [extra] entry wins on a name clash).
  final Map<String, Object?> extra;

  /// Adds/overrides an operation at [path] / [method].
  void putOperation(String path, String method, Operation op) {
    final byMethod = paths.putIfAbsent(path, () => <String, Operation>{});
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
    final guarded = paths.values
        .any((byMethod) => byMethod.values.any((op) => op.requiresAuth));
    final schemes =
        guarded ? securitySchemes : const <String, SecurityScheme>{};
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
            for (final op in entry.value.entries)
              op.key: op.value.toMap(securitySchemes: schemes.keys),
          },
      },
      if (_schemas.isNotEmpty || schemes.isNotEmpty)
        'components': <String, Object?>{
          if (_schemas.isNotEmpty) 'schemas': _schemas,
          if (schemes.isNotEmpty)
            'securitySchemes': <String, Object?>{
              for (final e in schemes.entries) e.key: e.value.toMap(),
            },
        },
    };
    for (final e in extra.entries) {
      final generated = out[e.key];
      final added = e.value;
      // `components` is merged one section (schemas, securitySchemes, …)
      // at a time, so extra entries add to the generated ones; on a name
      // clash the entry from [extra] wins.
      if (e.key == 'components' && generated is Map && added is Map) {
        out['components'] = <String, Object?>{
          for (final g in generated.entries) '${g.key}': g.value,
          for (final a in added.entries)
            '${a.key}': switch ((generated[a.key], a.value)) {
              (final Map<Object?, Object?> g, final Map<Object?, Object?> v) =>
                <String, Object?>{
                  for (final x in g.entries) '${x.key}': x.value,
                  for (final x in v.entries) '${x.key}': x.value,
                },
              _ => a.value,
            },
        };
      } else {
        out[e.key] = added;
      }
    }
    return out;
  }

  String toJson({bool pretty = true}) {
    final encoder =
        pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
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

/// An entry in `components.securitySchemes`.
class SecurityScheme {
  const SecurityScheme({
    required this.type,
    this.scheme,
    this.bearerFormat,
    this.name,
    this.location,
    this.description,
  });

  /// `Authorization: Bearer <token>`.
  const SecurityScheme.bearer(
      {String this.bearerFormat = 'JWT', this.description})
      : type = 'http',
        scheme = 'bearer',
        name = null,
        location = null;

  /// A key in a header, query parameter or cookie named [name].
  const SecurityScheme.apiKey({
    required String this.name,
    String this.location = 'header',
    this.description,
  })  : type = 'apiKey',
        scheme = null,
        bearerFormat = null;

  /// `http`, `apiKey`, `oauth2`, `openIdConnect` or `mutualTLS`.
  final String type;

  /// For `http`: `bearer`, `basic`, ...
  final String? scheme;
  final String? bearerFormat;

  /// For `apiKey`: the header, query or cookie name and where it goes.
  final String? name;
  final String? location;
  final String? description;

  Map<String, Object?> toMap() => <String, Object?>{
        'type': type,
        if (scheme != null) 'scheme': scheme,
        if (bearerFormat != null) 'bearerFormat': bearerFormat,
        if (name != null) 'name': name,
        if (location != null) 'in': location,
        if (description != null) 'description': description,
      };
}

/// The JSON body gisila sends with every error response.
const Map<String, Object?> errorEnvelopeSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'error': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'status': <String, Object?>{'type': 'integer'},
        'message': <String, Object?>{'type': 'string'},
        'code': <String, Object?>{'type': 'string'},
        'details': <String, Object?>{'type': 'object'},
      },
      'required': <String>['status', 'message'],
    },
  },
  'required': <String>['error'],
};

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
    this.requiresAuth = false,
    this.permissions = const <String>[],
    this.anyPermission = const <String>[],
    this.roles = const <String>[],
  });

  final String? summary;
  final String? description;
  final String? operationId;
  final bool deprecated;
  final List<String> tags;
  final List<Parameter> parameters;
  final RequestBody? requestBody;
  final Map<String, ResponseSpec> responses;

  /// Whether the route's guards require an authenticated caller.
  final bool requiresAuth;

  /// Permissions the caller must all hold.
  final List<String> permissions;

  /// Permissions of which the caller must hold at least one.
  final List<String> anyPermission;

  /// Roles the caller must all hold.
  final List<String> roles;

  /// [securitySchemes] are the document's scheme names. A guarded operation
  /// lists each as an alternative, carrying its required roles and
  /// permissions (OpenAPI 3.1 allows role names for non-OAuth schemes).
  /// The guards also appear as `x-gisila-guards`, since `anyPermission`
  /// has no standard form.
  Map<String, Object?> toMap({
    Iterable<String> securitySchemes = const <String>[],
  }) =>
      <String, Object?>{
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
        if (requiresAuth && securitySchemes.isNotEmpty)
          'security': <Object?>[
            for (final name in securitySchemes)
              <String, Object?>{
                name: <String>[...roles, ...permissions],
              },
          ],
        if (requiresAuth &&
            (permissions.isNotEmpty ||
                anyPermission.isNotEmpty ||
                roles.isNotEmpty))
          'x-gisila-guards': <String, Object?>{
            if (permissions.isNotEmpty) 'permissions': permissions,
            if (anyPermission.isNotEmpty) 'anyPermission': anyPermission,
            if (roles.isNotEmpty) 'roles': roles,
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
