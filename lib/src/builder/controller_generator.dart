/// `source_gen` Generator that turns each `@Controller` class into:
///
/// * an extension method `attachOpenApi(OpenApiSpec spec, Router router,
///   {String prefix = ''})` that registers the routes on a
///   shelf_router and contributes the operations to the spec, and
/// * inline JSON schemas for every Dart type referenced as a path /
///   query parameter or as a request / response body.
library gisila_doc.builder.controller_generator;

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import '../annotations.dart';
import 'schema_emitter.dart';
import 'utils.dart';

/// Maps Dart parameter classifications onto the OpenAPI `in` field.
enum _Source { path, query, header, body, request, none }

class ControllerGenerator extends GeneratorForAnnotation<Controller> {
  const ControllerGenerator();

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@Controller must be placed on a class.',
        element: element,
      );
    }

    final cls = element;
    final controllerPrefix = annotation.read('path').stringValue;
    final controllerTags = annotation
        .read('tags')
        .listValue
        .map((d) => d.toStringValue() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    final emitter = SchemaEmitter();
    final routeBlocks = <String>[];

    for (final method in cls.methods) {
      final route = _readRoute(method);
      if (route == null) continue;

      routeBlocks.add(_emitRoute(
        cls: cls,
        method: method,
        route: route,
        controllerPrefix: controllerPrefix,
        controllerTags: controllerTags,
        emitter: emitter,
      ));
    }

    if (routeBlocks.isEmpty) {
      // No annotated methods - emit nothing rather than a useless
      // extension. The user probably forgot to annotate.
      log.warning(
        'gisila_doc: ${cls.name} is annotated with @Controller but '
        'has no methods carrying @Get/@Post/...; skipping.',
      );
      return '';
    }

    // Emit a `spec.putSchema` call for every component schema the
    // emitter accumulated while traversing the parameter/return types.
    final schemaRegistrations = emitter.componentSchemas.entries
        .map((e) => "    spec.putSchema('${e.key}', ${e.value});")
        .join('\n');

    final tagRegistrations = controllerTags
        .map((t) => "    spec.putTag(${dartString(t)});")
        .join('\n');

    final buffer = StringBuffer()
      ..writeln('// **************************************************')
      ..writeln('// gisila_doc: generated for ${cls.name}')
      ..writeln('// **************************************************')
      ..writeln()
      ..writeln('extension ${cls.name}OpenApi on ${cls.name} {')
      ..writeln('  /// Registers every annotated route of this controller on')
      ..writeln('  /// [router] and contributes the operations to [spec].')
      ..writeln('  ///')
      ..writeln('  /// Pass [prefix] to mount the controller under an extra')
      ..writeln('  /// path segment (e.g. an `/api/v1` versioning prefix).')
      ..writeln('  void attachOpenApi(')
      ..writeln('    OpenApiSpec spec,')
      ..writeln('    Router router, {')
      ..writeln('    String prefix = \'\',')
      ..writeln('  }) {')
      ..writeln(schemaRegistrations)
      ..writeln(tagRegistrations)
      ..writeln(routeBlocks.join('\n'))
      ..writeln('  }')
      ..writeln('}');

    return buffer.toString();
  }

  // -------------------------------------------------------------------------
  // Per-method codegen
  // -------------------------------------------------------------------------

  String _emitRoute({
    required ClassElement cls,
    required MethodElement method,
    required _RouteMeta route,
    required String controllerPrefix,
    required List<String> controllerTags,
    required SchemaEmitter emitter,
  }) {
    final fullPath = _joinPath(controllerPrefix, route.path);
    final shelfPath = toShelfPath(fullPath);
    final placeholders = pathPlaceholders(fullPath).toSet();

    final paramInfos = _classifyParameters(
      method: method,
      placeholders: placeholders,
    );

    final argExprs = <String>[];
    final namedArgExprs = <String>[];
    final extractStatements = <String>[];
    final parameterEntries = <String>[];
    String? requestBodyEntry;

    for (final pi in paramInfos) {
      switch (pi.source) {
        case _Source.request:
          // Pass the shelf request straight through.
          if (pi.parameter.isNamed) {
            namedArgExprs.add('${pi.parameter.name}: request');
          } else {
            argExprs.add('request');
          }
          break;

        case _Source.path:
          final typeName = typeDisplayNameNullable(pi.parameter.type);
          extractStatements.add(
            'final ${pi.parameter.name} = coerce<$typeName>('
            "request.params[${dartString(pi.openApiName)}], "
            '${dartString(pi.openApiName)}, required: true);',
          );
          if (pi.parameter.isNamed) {
            namedArgExprs.add('${pi.parameter.name}: ${pi.parameter.name}');
          } else {
            argExprs.add(pi.parameter.name);
          }
          parameterEntries.add(
            "Parameter("
            "name: ${dartString(pi.openApiName)}, "
            "location: 'path', "
            'required: true, '
            'description: ${pi.description == null ? 'null' : dartString(pi.description!)}, '
            'schema: ${emitter.emitInline(pi.parameter.type)}, '
            ')',
          );
          break;

        case _Source.query:
          final typeName = typeDisplayNameNullable(pi.parameter.type);
          final required =
              !pi.parameter.isOptional && !isNullable(pi.parameter.type);
          extractStatements.add(
            'final ${pi.parameter.name} = coerce<$typeName>('
            "request.url.queryParameters[${dartString(pi.openApiName)}], "
            '${dartString(pi.openApiName)}, required: $required);',
          );
          if (pi.parameter.isNamed) {
            namedArgExprs.add('${pi.parameter.name}: ${pi.parameter.name}');
          } else {
            argExprs.add(pi.parameter.name);
          }
          parameterEntries.add(
            "Parameter("
            "name: ${dartString(pi.openApiName)}, "
            "location: 'query', "
            'required: $required, '
            'description: ${pi.description == null ? 'null' : dartString(pi.description!)}, '
            'schema: ${emitter.emitInline(pi.parameter.type)}, '
            ')',
          );
          break;

        case _Source.header:
          extractStatements.add(
            "final ${pi.parameter.name} = request.headers[${dartString(pi.openApiName.toLowerCase())}];",
          );
          if (pi.parameter.isNamed) {
            namedArgExprs.add('${pi.parameter.name}: ${pi.parameter.name}');
          } else {
            argExprs.add(pi.parameter.name);
          }
          parameterEntries.add(
            "Parameter("
            "name: ${dartString(pi.openApiName)}, "
            "location: 'header', "
            'required: ${!pi.parameter.isOptional && !isNullable(pi.parameter.type)}, '
            'description: ${pi.description == null ? 'null' : dartString(pi.description!)}, '
            'schema: ${emitter.emitInline(pi.parameter.type)}, '
            ')',
          );
          break;

        case _Source.body:
          final bodyDecoder = _bodyDecoderExpression(pi.parameter.type);
          extractStatements.add(
            'final __raw_${pi.parameter.name} = await readJsonBody(request, '
            'required: ${!pi.parameter.isOptional && !isNullable(pi.parameter.type)});',
          );
          extractStatements.add(
            'final ${pi.parameter.name} = '
            '${bodyDecoder(' __raw_${pi.parameter.name} ')};',
          );
          if (pi.parameter.isNamed) {
            namedArgExprs.add('${pi.parameter.name}: ${pi.parameter.name}');
          } else {
            argExprs.add(pi.parameter.name);
          }
          requestBodyEntry =
              "RequestBody(required: ${!pi.parameter.isOptional && !isNullable(pi.parameter.type)}, "
              'content: {'
              "'application/json': MediaType(schema: ${emitter.emitInline(pi.parameter.type)})"
              '})';
          break;

        case _Source.none:
          throw InvalidGenerationSourceError(
            'Could not classify parameter "${pi.parameter.name}" of '
            '${cls.name}.${method.name}. Annotate it with @Path, @Query, '
            '@Header or @Body, or remove it.',
            element: pi.parameter,
          );
      }
    }

    // ---------- response handling ----------
    final returnType = unwrapFuture(method.returnType);
    final returnsResponse = isShelfResponse(returnType);
    final returnsVoid = isVoid(method.returnType);

    final callArgs = StringBuffer('this.${method.name}(');
    callArgs.write(argExprs.join(', '));
    if (namedArgExprs.isNotEmpty) {
      if (argExprs.isNotEmpty) callArgs.write(', ');
      callArgs.write(namedArgExprs.join(', '));
    }
    callArgs.write(')');

    String handlerBody;
    if (returnsResponse) {
      handlerBody = '''
${extractStatements.join('\n          ')}
          final response = await $callArgs;
          return response;
      ''';
    } else if (returnsVoid) {
      handlerBody = '''
${extractStatements.join('\n          ')}
          await $callArgs;
          return emptyResponse(statusCode: ${route.successStatus});
      ''';
    } else {
      handlerBody = '''
${extractStatements.join('\n          ')}
          final result = await $callArgs;
          return jsonResponse(body: result, statusCode: ${route.successStatus});
      ''';
    }

    // ---------- extra query params from @QueryDoc ----------
    for (final qd in route.extraQueryDocs) {
      final schema = qd.type != null
          ? emitter.emitInline(qd.type!)
          : "<String, Object?>{'type': 'string'}";
      parameterEntries.add(
        "Parameter("
        "name: ${dartString(qd.name)}, "
        "location: 'query', "
        'required: ${qd.required}, '
        'description: ${qd.description == null ? 'null' : dartString(qd.description!)}, '
        'schema: $schema, '
        ')',
      );
    }

    // ---------- request body (from @RequestBody when no typed param) ----------
    if (requestBodyEntry == null && route.bodyDoc != null) {
      final bd = route.bodyDoc!;
      final schema = emitter.emitInline(bd.type);
      requestBodyEntry = 'RequestBody(required: ${bd.required}, '
          'content: {'
          "'${bd.contentType}': MediaType(schema: $schema)"
          '}'
          '${bd.description != null ? ", description: ${dartString(bd.description!)}" : ""}'
          ')';
    }

    // ---------- responses spec ----------
    // When the method returns Future<Response> but @Returns(bodyType:) or
    // @ApiResponse(bodyType:) was supplied, use that type for the schema.
    String? responseSchema;
    if (!returnsVoid) {
      if (!returnsResponse) {
        responseSchema = emitter.emitInline(returnType);
      } else if (route.returnsBodyType != null) {
        responseSchema = emitter.emitInline(route.returnsBodyType!);
      }
    }

    final responsesEntries = <String>[];
    final defaultDesc = route.successDescription ??
        _defaultStatusDescription(route.successStatus);

    if (responseSchema == null) {
      responsesEntries.add(
        "'${route.successStatus}': ResponseSpec(description: ${dartString(defaultDesc)})",
      );
    } else {
      responsesEntries.add(
        "'${route.successStatus}': ResponseSpec(description: ${dartString(defaultDesc)}, "
        'content: {'
        "'application/json': MediaType(schema: $responseSchema)"
        '})',
      );
    }
    for (final extra in route.extraResponses) {
      final extraDesc = dartString(
          extra.description ?? _defaultStatusDescription(extra.statusCode));
      if (extra.bodyType != null) {
        final extraSchema = emitter.emitInline(extra.bodyType!);
        responsesEntries.add(
          "'${extra.statusCode}': ResponseSpec(description: $extraDesc, "
          'content: {'
          "'application/json': MediaType(schema: $extraSchema)"
          '})',
        );
      } else {
        responsesEntries.add(
          "'${extra.statusCode}': ResponseSpec(description: $extraDesc)",
        );
      }
    }

    final tags = <String>{...controllerTags, ...route.tags}.toList();
    final tagsLiteral = tags.isEmpty
        ? '<String>[]'
        : '<String>[${tags.map(dartString).join(', ')}]';

    final paramsLiteral = parameterEntries.isEmpty
        ? '<Parameter>[]'
        : '<Parameter>[${parameterEntries.join(', ')}]';

    final operationFields = <String>[
      if (route.summary != null) 'summary: ${dartString(route.summary!)}',
      if (route.description != null)
        'description: ${dartString(route.description!)}',
      if (route.operationId != null)
        'operationId: ${dartString(route.operationId!)}',
      if (route.deprecated) 'deprecated: true',
      'tags: $tagsLiteral',
      'parameters: $paramsLiteral',
      if (requestBodyEntry != null) 'requestBody: $requestBodyEntry',
      'responses: <String, ResponseSpec>{${responsesEntries.join(', ')}}',
    ];

    return '''
    {
      final basePath = '\$prefix$shelfPath';
      final openApiPath = '\$prefix$fullPath';
      router.${route.method.toLowerCase()}(basePath, (Request request) async {
        try {
          $handlerBody
        } on BadRequestException catch (e) {
          return Response(400, body: '{"error":"\${e.message}"}', headers: const {'content-type': 'application/json'});
        } on TypeError catch (e) {
          return Response(400, body: '{"error":"Invalid request payload (\$e)"}', headers: const {'content-type': 'application/json'});
        } on FormatException catch (e) {
          return Response(400, body: '{"error":"Invalid request format: \${e.message}"}', headers: const {'content-type': 'application/json'});
        }
      });
      spec.putOperation(openApiPath, '${route.method.toLowerCase()}', Operation(
        ${operationFields.join(',\n        ')},
      ));
    }''';
  }

  // -------------------------------------------------------------------------
  // Annotation reading
  // -------------------------------------------------------------------------

  _RouteMeta? _readRoute(MethodElement method) {
    ConstantReader? reader;
    String? httpMethod;
    for (final m in method.metadata) {
      final value = m.computeConstantValue();
      if (value == null) continue;
      final type = value.type;
      if (type == null) continue;
      final element = type.element;
      if (element is! ClassElement) continue;
      if (!_isRouteSubtype(element)) continue;
      // ConstantReader.read walks inheritance, so the `method` field
      // declared on the Route super class is found here.
      reader = ConstantReader(value);
      httpMethod = reader.peek('method')?.stringValue;
      break;
    }
    if (reader == null || httpMethod == null) return null;

    final path = reader.read('path').stringValue;
    final summary = reader.peek('summary')?.stringValue;
    final description = reader.peek('description')?.stringValue;
    final operationId = reader.peek('operationId')?.stringValue;
    final deprecated = reader.peek('deprecated')?.boolValue ?? false;
    final tags = (reader.peek('tags')?.listValue ?? const <DartObject>[])
        .map((d) => d.toStringValue() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    final statusCode = reader.peek('statusCode')?.intValue ?? 200;

    // Honor @Returns / @Responses, @ApiResponse extras, @RequestBody, and @QueryDoc.
    int? overrideStatus;
    String? overrideDesc;
    DartType? returnsBodyType;
    _BodyDocMeta? bodyDoc;
    final extraQueryDocs = <_QueryDocMeta>[];
    final extras = <_ExtraResponse>[];

    // Collects all @Returns entries (from stacked @Returns and from @Responses).
    // First entry → primary success response override; rest → extra responses.
    final returnsEntries = <_ReturnsEntry>[];

    for (final m in method.metadata) {
      final value = m.computeConstantValue();
      if (value == null) continue;
      final type = value.type;
      final element = type?.element;
      if (element is! ClassElement) continue;
      final r = ConstantReader(value);
      if (element.name == 'Returns') {
        returnsEntries.add(_ReturnsEntry._fromReader(r));
      } else if (element.name == 'Responses') {
        for (final item in r.read('responses').listValue) {
          returnsEntries.add(_ReturnsEntry._fromReader(ConstantReader(item)));
        }
      } else if (element.name == 'ApiResponse') {
        final s = r.peek('statusCode')?.intValue;
        final d = r.peek('description')?.stringValue;
        DartType? bodyType;
        final btReader = r.peek('bodyType');
        if (btReader != null && !btReader.isNull) {
          bodyType = btReader.typeValue;
        }
        if (s != null) {
          extras.add(_ExtraResponse(
            statusCode: s,
            description: d,
            bodyType: bodyType,
          ));
        }
      } else if (element.name == 'BodyDoc') {
        final typeReader = r.read('type');
        bodyDoc = _BodyDocMeta(
          type: typeReader.typeValue,
          required: r.peek('required')?.boolValue ?? true,
          description: r.peek('description')?.stringValue,
          contentType: r.peek('contentType')?.stringValue ?? 'application/json',
        );
      } else if (element.name == 'QueryDoc') {
        final name = r.read('name').stringValue;
        final typeReader = r.peek('type');
        final dartType = (typeReader != null && !typeReader.isNull)
            ? typeReader.typeValue
            : null;
        extraQueryDocs.add(_QueryDocMeta(
          name: name,
          type: dartType,
          required: r.peek('required')?.boolValue ?? false,
          description: r.peek('description')?.stringValue,
        ));
      }
    }

    // Fall back to inline body:/responses: from the route annotation when no
    // standalone method-level annotations provided those values.
    if (bodyDoc == null) {
      final inlineBody = reader.peek('body');
      if (inlineBody != null && !inlineBody.isNull) {
        bodyDoc = _BodyDocMeta(
          type: inlineBody.read('type').typeValue,
          required: inlineBody.peek('required')?.boolValue ?? true,
          description: inlineBody.peek('description')?.stringValue,
          contentType:
              inlineBody.peek('contentType')?.stringValue ?? 'application/json',
        );
      }
    }

    if (returnsEntries.isEmpty) {
      final inlineResponses = reader.peek('responses');
      if (inlineResponses != null && !inlineResponses.isNull) {
        for (final item in inlineResponses.listValue) {
          returnsEntries.add(_ReturnsEntry._fromReader(ConstantReader(item)));
        }
      }
    }

    // Process collected @Returns / @Responses entries.
    // First entry overrides the primary success response; the rest become
    // additional response entries (like @ApiResponse).
    if (returnsEntries.isNotEmpty) {
      final primary = returnsEntries.first;
      overrideStatus = primary.statusCode;
      overrideDesc = primary.description;
      returnsBodyType = primary.bodyType;
      for (final entry in returnsEntries.skip(1)) {
        final s = entry.statusCode;
        if (s != null) {
          extras.add(_ExtraResponse(
            statusCode: s,
            description: entry.description,
            bodyType: entry.bodyType,
          ));
        }
      }
    }

    return _RouteMeta(
      method: httpMethod,
      path: path,
      summary: summary,
      description: description,
      operationId: operationId,
      deprecated: deprecated,
      tags: tags,
      successStatus: overrideStatus ?? statusCode,
      successDescription: overrideDesc,
      extraResponses: extras,
      returnsBodyType: returnsBodyType,
      bodyDoc: bodyDoc,
      extraQueryDocs: extraQueryDocs,
    );
  }

  bool _isRouteSubtype(ClassElement element) {
    ClassElement? c = element;
    while (c != null) {
      if (c.name == 'Route' && c.library.identifier.contains('gisila_doc')) {
        return true;
      }
      final superType = c.supertype;
      if (superType == null) break;
      final superElement = superType.element;
      c = superElement is ClassElement ? superElement : null;
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Parameter classification
  // -------------------------------------------------------------------------

  List<_ParamInfo> _classifyParameters({
    required MethodElement method,
    required Set<String> placeholders,
  }) {
    final infos = <_ParamInfo>[];
    bool bodySeen = false;
    for (final p in method.parameters) {
      // Explicit annotations win.
      final annot = _findParamAnnotation(p);
      if (annot != null) {
        infos.add(_ParamInfo(
          parameter: p,
          source: annot.source,
          openApiName: annot.name ?? p.name,
          description: annot.description,
        ));
        if (annot.source == _Source.body) bodySeen = true;
        continue;
      }

      // shelf Request always passes through.
      if (isShelfRequest(p.type)) {
        infos.add(_ParamInfo(
          parameter: p,
          source: _Source.request,
          openApiName: p.name,
        ));
        continue;
      }

      // Implicit @Path when the name matches a placeholder.
      if (placeholders.contains(p.name)) {
        infos.add(_ParamInfo(
          parameter: p,
          source: _Source.path,
          openApiName: p.name,
        ));
        continue;
      }

      // Primitive ⇒ implicit query parameter.
      if (isCoercible(p.type)) {
        infos.add(_ParamInfo(
          parameter: p,
          source: _Source.query,
          openApiName: p.name,
        ));
        continue;
      }

      // Anything else (custom class, List<X>, Map<String,V>) is the
      // body. We allow at most one implicit body parameter.
      if (!bodySeen) {
        infos.add(_ParamInfo(
          parameter: p,
          source: _Source.body,
          openApiName: p.name,
        ));
        bodySeen = true;
        continue;
      }

      infos.add(_ParamInfo(
        parameter: p,
        source: _Source.none,
        openApiName: p.name,
      ));
    }
    return infos;
  }

  _ParamAnnotation? _findParamAnnotation(ParameterElement p) {
    for (final m in p.metadata) {
      final value = m.computeConstantValue();
      if (value == null) continue;
      final type = value.type;
      final element = type?.element;
      if (element is! ClassElement) continue;
      switch (element.name) {
        case 'Path':
          return _ParamAnnotation(
            source: _Source.path,
            name: value.getField('name')?.toStringValue(),
            description: value.getField('description')?.toStringValue(),
          );
        case 'Query':
          return _ParamAnnotation(
            source: _Source.query,
            name: value.getField('name')?.toStringValue(),
            description: value.getField('description')?.toStringValue(),
          );
        case 'Header':
          return _ParamAnnotation(
            source: _Source.header,
            name: value.getField('name')?.toStringValue(),
            description: value.getField('description')?.toStringValue(),
          );
        case 'Body':
          return _ParamAnnotation(
            source: _Source.body,
            name: null,
            description: value.getField('description')?.toStringValue(),
          );
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  String _joinPath(String prefix, String suffix) {
    final p =
        prefix.endsWith('/') ? prefix.substring(0, prefix.length - 1) : prefix;
    final s = suffix.startsWith('/') ? suffix : '/$suffix';
    final out = '$p$s';
    return out.isEmpty ? '/' : out;
  }

  String Function(String expr) _bodyDecoderExpression(DartType type) {
    final inner = listElementType(type);
    if (inner != null && inner is InterfaceType) {
      final innerElement = inner.element;
      if (innerElement is ClassElement &&
          fromJsonConstructor(innerElement) != null) {
        final n = innerElement.name;
        return (raw) => '($raw as List)'
            '.map((e) => $n.fromJson(e as Map<String, dynamic>))'
            '.toList()';
      }
      return (raw) => '($raw as List)';
    }

    if (isStringMap(type)) {
      return (raw) => '($raw as Map).cast<String, dynamic>()';
    }

    if (type is InterfaceType) {
      final element = type.element;
      if (element is ClassElement && fromJsonConstructor(element) != null) {
        final n = element.name;
        return (raw) => '$n.fromJson($raw as Map<String, dynamic>)';
      }
      // Built-in `Map<String, dynamic>` falls through too.
      if (type.isDartCoreMap) {
        return (raw) => '($raw as Map).cast<String, dynamic>()';
      }
    }

    // Last resort: pass through raw decoded JSON.
    return (raw) => raw;
  }

  String _defaultStatusDescription(int code) {
    switch (code) {
      case 200:
        return 'OK';
      case 201:
        return 'Created';
      case 202:
        return 'Accepted';
      case 204:
        return 'No Content';
      case 301:
        return 'Moved Permanently';
      case 302:
        return 'Found';
      case 400:
        return 'Bad Request';
      case 401:
        return 'Unauthorized';
      case 403:
        return 'Forbidden';
      case 404:
        return 'Not Found';
      case 409:
        return 'Conflict';
      case 422:
        return 'Unprocessable Entity';
      case 500:
        return 'Internal Server Error';
      default:
        return 'Status $code';
    }
  }
}

class _RouteMeta {
  _RouteMeta({
    required this.method,
    required this.path,
    required this.summary,
    required this.description,
    required this.operationId,
    required this.deprecated,
    required this.tags,
    required this.successStatus,
    required this.successDescription,
    required this.extraResponses,
    this.returnsBodyType,
    this.bodyDoc,
    this.extraQueryDocs = const [],
  });

  final String method;
  final String path;
  final String? summary;
  final String? description;
  final String? operationId;
  final bool deprecated;
  final List<String> tags;
  final int successStatus;
  final String? successDescription;
  final List<_ExtraResponse> extraResponses;

  /// Body type supplied via `@Returns(bodyType: T)` when the method
  /// returns `Future<Response>` directly.
  final DartType? returnsBodyType;

  /// Request body schema declared via `@RequestBody(T)` at method level.
  final _BodyDocMeta? bodyDoc;

  /// Extra query parameters declared via `@QueryDoc` at method level.
  final List<_QueryDocMeta> extraQueryDocs;
}

class _ExtraResponse {
  _ExtraResponse({
    required this.statusCode,
    this.description,
    this.bodyType,
  });
  final int statusCode;
  final String? description;

  /// Body type supplied via `@ApiResponse(statusCode, bodyType: T)`.
  final DartType? bodyType;
}

class _BodyDocMeta {
  _BodyDocMeta({
    required this.type,
    required this.required,
    required this.contentType,
    this.description,
  });
  final DartType type;
  final bool required;
  final String contentType;
  final String? description;
}

class _QueryDocMeta {
  _QueryDocMeta({
    required this.name,
    required this.required,
    this.type,
    this.description,
  });
  final String name;

  /// Null means the annotation did not supply a type; fall back to string.
  final DartType? type;
  final bool required;
  final String? description;
}

class _ParamInfo {
  _ParamInfo({
    required this.parameter,
    required this.source,
    required this.openApiName,
    this.description,
  });
  final ParameterElement parameter;
  final _Source source;
  final String openApiName;
  final String? description;
}

class _ParamAnnotation {
  _ParamAnnotation({required this.source, this.name, this.description});
  final _Source source;
  final String? name;
  final String? description;
}

/// Internal representation of a single entry from `@Returns` or `@Responses`.
class _ReturnsEntry {
  _ReturnsEntry({this.statusCode, this.description, this.bodyType});

  factory _ReturnsEntry._fromReader(ConstantReader r) {
    final statusCode = r.peek('statusCode')?.intValue;
    final description = r.peek('description')?.stringValue;
    DartType? bodyType;
    final btReader = r.peek('bodyType');
    if (btReader != null && !btReader.isNull) {
      bodyType = btReader.typeValue;
    }
    return _ReturnsEntry(
      statusCode: statusCode,
      description: description,
      bodyType: bodyType,
    );
  }

  final int? statusCode;
  final String? description;
  final DartType? bodyType;
}
