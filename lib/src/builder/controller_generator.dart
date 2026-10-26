/// `source_gen` Generator that turns each `@Controller` class into an
/// extension method
/// `attachToApp(GisilaApp app, Router router, OpenApiSpec spec,
/// {String prefix = ''})` which:
///
/// 1. Registers every annotated route on the [Router] through
///    [gisilaRoute] - so the runtime path goes through the same MVC
///    pipeline (per-route rate limit / timeout / content-type filter
///    / AuthN+AuthZ / error mapping) as the gisila core generator.
/// 2. Contributes the matching operation, schemas and tags to the
///    shared [OpenApiSpec].
///
/// The generator deliberately reuses gisila's `RouteConfig` literal
/// emitter (`package:gisila/builder_helpers.dart`) so the per-route
/// config merging logic stays in lock-step with the core generator.
library gisila_doc.builder.controller_generator;

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:gisila/builder_helpers.dart' as gisila_builder;
import 'package:source_gen/source_gen.dart';

import '../annotations.dart';
import 'schema_emitter.dart';
import 'utils.dart';

/// Maps Dart parameter classifications onto the OpenAPI `in` field /
/// gisila handler-binding strategy.
enum _Source {
  path,
  query,
  header,
  body,
  request,
  context,
  form,
  service,
  none,
}

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

    final classGuards = _readGuards(cls.metadata);
    final classMiddleware = _readMiddlewareNames(cls.metadata);
    final classRouteConfig = _readUseRouteConfig(cls.metadata);

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
        classGuards: classGuards,
        classMiddleware: classMiddleware,
        classRouteConfig: classRouteConfig,
        emitter: emitter,
      ));
    }

    if (routeBlocks.isEmpty) {
      log.warning(
        'gisila_doc: ${cls.name} is annotated with @Controller but '
        'has no methods carrying @Get/@Post/...; skipping.',
      );
      return '';
    }

    // `spec.putSchema(...)` once per accumulated component schema.
    final schemaRegistrations = emitter.componentSchemas.entries
        .map((e) => "    spec.putSchema('${e.key}', ${e.value});")
        .join('\n');

    final tagRegistrations = controllerTags
        .map((t) => "    spec.putTag(${gisila_builder.dartString(t)});")
        .join('\n');

    final buffer = StringBuffer()
      ..writeln('// **************************************************')
      ..writeln('// gisila_doc: generated for ${cls.name}')
      ..writeln('// **************************************************')
      ..writeln()
      ..writeln('extension ${cls.name}GisilaDoc on ${cls.name} {')
      ..writeln('  /// Registers every annotated route of this controller on')
      ..writeln('  /// [router] (through `gisilaRoute(...)` so the route runs')
      ..writeln('  /// through the same MVC pipeline as gisila core) and')
      ..writeln('  /// contributes the matching operations / schemas / tags')
      ..writeln('  /// to [spec].')
      ..writeln('  ///')
      ..writeln('  /// Pass [prefix] to mount the controller under an extra')
      ..writeln('  /// path segment (e.g. an `/api/v1` versioning prefix).')
      ..writeln('  void attachToApp(')
      ..writeln('    GisilaApp app,')
      ..writeln('    Router router,')
      ..writeln('    OpenApiSpec spec, {')
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
  // Per-route codegen
  // -------------------------------------------------------------------------

  String _emitRoute({
    required ClassElement cls,
    required MethodElement method,
    required _RouteMeta route,
    required String controllerPrefix,
    required List<String> controllerTags,
    required _Guards classGuards,
    required List<String> classMiddleware,
    required DartObject? classRouteConfig,
    required SchemaEmitter emitter,
  }) {
    final fullPath = _joinPath(controllerPrefix, route.path);
    final shelfPath = toShelfPath(fullPath);
    final placeholders = pathPlaceholders(fullPath).toSet();

    final methodGuards = _readGuards(method.metadata);
    final methodMiddleware = _readMiddlewareNames(method.metadata);

    final effectiveGuards = methodGuards.isPublic
        ? const _Guards.public()
        : _mergeGuards(classGuards, methodGuards);

    final paramInfos = _classifyParameters(
      method: method,
      placeholders: placeholders,
    );

    final wantsContext = paramInfos.any((p) => p.source == _Source.context);
    final wantsRequest = paramInfos.any((p) => p.source == _Source.request);

    final argExprs = <String>[];
    final namedArgExprs = <String>[];
    final extractStatements = <String>[];
    final parameterEntries = <String>[];
    String? requestBodyEntry;

    for (final pi in paramInfos) {
      switch (pi.source) {
        case _Source.request:
          _appendArgWith(argExprs, namedArgExprs, pi, 'request');
          break;

        case _Source.context:
          _appendArgWith(argExprs, namedArgExprs, pi, 'ctx');
          break;

        case _Source.form:
          final typeName = typeDisplayName(pi.parameter.type);
          extractStatements.add(
            'final ${pi.parameter.name} = '
            'await bindForm(request, $typeName.new);',
          );
          _appendArgWith(argExprs, namedArgExprs, pi, pi.parameter.name);
          // Contribute the form's JSON Schema to the OpenAPI body.
          final schema = emitter.emitInline(pi.parameter.type);
          requestBodyEntry =
              'RequestBody(required: ${!pi.parameter.isOptional && !isNullable(pi.parameter.type)}, '
              'content: {'
              "'application/json': MediaType(schema: $schema)"
              '})';
          break;

        case _Source.service:
          final typeName = typeDisplayName(pi.parameter.type);
          extractStatements.add(
            'final ${pi.parameter.name} = ctx.service<$typeName>();',
          );
          _appendArgWith(argExprs, namedArgExprs, pi, pi.parameter.name);
          break;

        case _Source.path:
          final typeName = typeDisplayNameNullable(pi.parameter.type);
          extractStatements.add(
            'final ${pi.parameter.name} = coerce<$typeName>('
            "request.params[${_dartStr(pi.openApiName)}], "
            '${_dartStr(pi.openApiName)}, required: true);',
          );
          _appendArgWith(argExprs, namedArgExprs, pi, pi.parameter.name);
          parameterEntries.add(
            "Parameter("
            "name: ${_dartStr(pi.openApiName)}, "
            "location: 'path', "
            'required: true, '
            'description: ${pi.description == null ? 'null' : _dartStr(pi.description!)}, '
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
            "request.url.queryParameters[${_dartStr(pi.openApiName)}], "
            '${_dartStr(pi.openApiName)}, required: $required);',
          );
          _appendArgWith(argExprs, namedArgExprs, pi, pi.parameter.name);
          parameterEntries.add(
            "Parameter("
            "name: ${_dartStr(pi.openApiName)}, "
            "location: 'query', "
            'required: $required, '
            'description: ${pi.description == null ? 'null' : _dartStr(pi.description!)}, '
            'schema: ${emitter.emitInline(pi.parameter.type)}, '
            ')',
          );
          break;

        case _Source.header:
          extractStatements.add(
            "final ${pi.parameter.name} = request.headers[${_dartStr(pi.openApiName.toLowerCase())}];",
          );
          _appendArgWith(argExprs, namedArgExprs, pi, pi.parameter.name);
          parameterEntries.add(
            "Parameter("
            "name: ${_dartStr(pi.openApiName)}, "
            "location: 'header', "
            'required: ${!pi.parameter.isOptional && !isNullable(pi.parameter.type)}, '
            'description: ${pi.description == null ? 'null' : _dartStr(pi.description!)}, '
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
          _appendArgWith(argExprs, namedArgExprs, pi, pi.parameter.name);
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
            '@Header or @Body, declare it as a Form / Service subtype, '
            'or remove it.',
            element: pi.parameter,
          );
      }
    }

    // ---------- response handling ----------
    final returnType = unwrapFuture(method.returnType);
    final returnsResponse = isShelfResponse(returnType);
    final returnsVoid = isVoid(method.returnType);

    final successStatus = route.successStatus;

    final callArgs = StringBuffer('this.${method.name}(')
      ..write(argExprs.join(', '));
    if (namedArgExprs.isNotEmpty) {
      if (argExprs.isNotEmpty) callArgs.write(', ');
      callArgs.write(namedArgExprs.join(', '));
    }
    callArgs.write(')');

    String returnStmt;
    if (returnsResponse) {
      returnStmt = '''final response = await $callArgs;
            return response;''';
    } else if (returnsVoid) {
      returnStmt = '''await $callArgs;
            return emptyResponse(statusCode: $successStatus);''';
    } else {
      returnStmt = '''final result = await $callArgs;
            return jsonResponse(body: result, statusCode: $successStatus);''';
    }

    final extractBlock = extractStatements.isEmpty
        ? ''
        : '${extractStatements.join('\n            ')}\n            ';

    // Decide whether to emit a `final request = ctx.request;` alias.
    final requestRe = RegExp(r'\brequest\b');
    final needsRequest =
        wantsRequest || extractStatements.any((s) => requestRe.hasMatch(s));
    final requestAlias =
        needsRequest ? 'final request = ctx.request;\n            ' : '';

    if (wantsContext) {/* ctx is consumed by the user method */}

    // ---------- extra query params from @QueryDoc ----------
    for (final qd in route.extraQueryDocs) {
      final schema = qd.type != null
          ? emitter.emitInline(qd.type!)
          : "<String, Object?>{'type': 'string'}";
      parameterEntries.add(
        "Parameter("
        "name: ${_dartStr(qd.name)}, "
        "location: 'query', "
        'required: ${qd.required}, '
        'description: ${qd.description == null ? 'null' : _dartStr(qd.description!)}, '
        'schema: $schema, '
        ')',
      );
    }

    // ---------- request body (from @BodyDoc when no typed param) ----------
    if (requestBodyEntry == null && route.bodyDoc != null) {
      final bd = route.bodyDoc!;
      final schema = emitter.emitInline(bd.type);
      requestBodyEntry = 'RequestBody(required: ${bd.required}, '
          'content: {'
          "'${bd.contentType}': MediaType(schema: $schema)"
          '}'
          '${bd.description != null ? ", description: ${_dartStr(bd.description!)}" : ""}'
          ')';
    }

    // ---------- responses spec ----------
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
        "'${route.successStatus}': ResponseSpec(description: ${_dartStr(defaultDesc)})",
      );
    } else {
      responsesEntries.add(
        "'${route.successStatus}': ResponseSpec(description: ${_dartStr(defaultDesc)}, "
        'content: {'
        "'application/json': MediaType(schema: $responseSchema)"
        '})',
      );
    }
    for (final extra in route.extraResponses) {
      final extraDesc = _dartStr(
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

    // Guarded routes document the 401 (and, with permissions or roles, the
    // 403) that the guards send, unless the route declares its own.
    if (effectiveGuards.requireAuth) {
      final declared = {
        route.successStatus,
        for (final extra in route.extraResponses) extra.statusCode,
      };
      final authz = effectiveGuards.permissions.isNotEmpty ||
          effectiveGuards.anyPermission.isNotEmpty ||
          effectiveGuards.roles.isNotEmpty;
      for (final status in [401, if (authz) 403]) {
        if (declared.contains(status)) continue;
        responsesEntries.add(
          "'$status': ResponseSpec(description: "
          '${_dartStr(_defaultStatusDescription(status))}, content: {'
          "'application/json': MediaType(schema: errorEnvelopeSchema)"
          '})',
        );
      }
    }

    final tags = <String>{...controllerTags, ...route.tags}.toList();
    final tagsLiteral = tags.isEmpty
        ? '<String>[]'
        : '<String>[${tags.map(_dartStr).join(', ')}]';

    final paramsLiteral = parameterEntries.isEmpty
        ? '<Parameter>[]'
        : '<Parameter>[${parameterEntries.join(', ')}]';

    final operationFields = <String>[
      if (route.summary != null) 'summary: ${_dartStr(route.summary!)}',
      if (route.description != null)
        'description: ${_dartStr(route.description!)}',
      if (route.operationId != null)
        'operationId: ${_dartStr(route.operationId!)}',
      if (route.deprecated) 'deprecated: true',
      'tags: $tagsLiteral',
      'parameters: $paramsLiteral',
      if (requestBodyEntry != null) 'requestBody: $requestBodyEntry',
      'responses: <String, ResponseSpec>{${responsesEntries.join(', ')}}',
      if (effectiveGuards.requireAuth) 'requiresAuth: true',
      if (effectiveGuards.permissions.isNotEmpty)
        'permissions: ${_stringList(effectiveGuards.permissions)}',
      if (effectiveGuards.anyPermission.isNotEmpty)
        'anyPermission: ${_stringList(effectiveGuards.anyPermission)}',
      if (effectiveGuards.roles.isNotEmpty)
        'roles: ${_stringList(effectiveGuards.roles)}',
    ];

    // ---------- route config literal ----------
    final classConfigLiteral =
        gisila_builder.emitRouteConfigLiteral(classRouteConfig);
    final guardsConfigLiteral = gisila_builder.emitGuardsRouteConfigLiteral(
      requireAuth: effectiveGuards.requireAuth,
      permissions: effectiveGuards.permissions,
      anyPermission: effectiveGuards.anyPermission,
      roles: effectiveGuards.roles,
      isPublic: effectiveGuards.isPublic,
    );
    final methodConfigLiteral =
        gisila_builder.emitRouteConfigLiteral(route.config);

    final mergedNamedMw = <String>{...classMiddleware, ...methodMiddleware};
    final namedMwConfigLiteral =
        gisila_builder.emitNamedMiddlewareConfig(mergedNamedMw);

    final mergeChain = StringBuffer(classConfigLiteral);
    if (guardsConfigLiteral != 'RouteConfig.empty') {
      mergeChain.write('.merge($guardsConfigLiteral)');
    }
    if (methodConfigLiteral != 'RouteConfig.empty') {
      mergeChain.write('.merge($methodConfigLiteral)');
    }
    if (namedMwConfigLiteral != null) {
      mergeChain.write('.merge($namedMwConfigLiteral)');
    }

    final cfgExpr = mergeChain.toString();

    return '''
    {
      final basePath = '\$prefix$shelfPath';
      final openApiPath = '\$prefix$fullPath';
      final RouteConfig __cfg = $cfgExpr;
      router.${route.method.toLowerCase()}(basePath, gisilaRoute(
        app: app,
        config: __cfg,
        handler: (RequestContext ctx) async {
          try {
            $requestAlias$extractBlock$returnStmt
          } on TypeError catch (e) {
            throw BadRequestException('Invalid request payload (\$e)');
          } on FormatException catch (e) {
            throw BadRequestException('Invalid request format: \${e.message}');
          }
        },
      ));
      spec.putOperation(openApiPath, '${route.method.toLowerCase()}', Operation(
        ${operationFields.join(',\n        ')},
      ));
    }''';
  }

  String _stringList(Iterable<String> values) =>
      '<String>[${(values.toList()..sort()).map(_dartStr).join(', ')}]';

  void _appendArgWith(
    List<String> positional,
    List<String> named,
    _ParamInfo pi,
    String value,
  ) {
    if (pi.parameter.isNamed) {
      named.add('${pi.parameter.name}: $value');
    } else {
      positional.add(value);
    }
  }

  // -------------------------------------------------------------------------
  // Annotation reading
  // -------------------------------------------------------------------------

  _RouteMeta? _readRoute(MethodElement method) {
    ConstantReader? reader;
    String? httpMethod;
    DartObject? config;
    for (final m in method.metadata) {
      final value = m.computeConstantValue();
      if (value == null) continue;
      final type = value.type;
      if (type == null) continue;
      final element = type.element;
      if (element is! ClassElement) continue;
      if (!_isRouteSubtype(element)) continue;
      reader = ConstantReader(value);
      httpMethod = reader.peek('method')?.stringValue;
      final cfg = reader.peek('config');
      if (cfg != null && !cfg.isNull) config = cfg.objectValue;
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

    int? overrideStatus;
    String? overrideDesc;
    DartType? returnsBodyType;
    _BodyDocMeta? bodyDoc;
    final extraQueryDocs = <_QueryDocMeta>[];
    final extras = <_ExtraResponse>[];
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
      config: config,
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

  /// Reads the (optional) class-level `@UseRouteConfig(config)`.
  DartObject? _readUseRouteConfig(List<ElementAnnotation> metadata) {
    for (final m in metadata) {
      final value = m.computeConstantValue();
      if (value == null) continue;
      final type = value.type;
      final element = type?.element;
      if (element is! ClassElement) continue;
      if (element.name != 'UseRouteConfig') continue;
      if (!element.library.identifier.contains('gisila')) continue;
      final cfg = value.getField('config');
      if (cfg != null && !cfg.isNull) return cfg;
    }
    return null;
  }

  _Guards _readGuards(List<ElementAnnotation> metadata) {
    var requireAuth = false;
    final perms = <String>{};
    final anyPerm = <String>{};
    final roles = <String>{};
    var isPublic = false;

    for (final m in metadata) {
      final value = m.computeConstantValue();
      if (value == null) continue;
      final type = value.type;
      final element = type?.element;
      if (element is! ClassElement) continue;
      if (!element.library.identifier.contains('gisila')) continue;

      switch (element.name) {
        case 'RequireAuth':
          requireAuth = true;
          break;
        case 'Public':
          isPublic = true;
          break;
        case 'Permissions':
          requireAuth = true;
          perms.addAll(_readStringSet(value, 'values'));
          break;
        case 'AnyPermission':
          requireAuth = true;
          anyPerm.addAll(_readStringSet(value, 'values'));
          break;
        case 'Roles':
          requireAuth = true;
          roles.addAll(_readStringSet(value, 'values'));
          break;
      }
    }

    return _Guards(
      requireAuth: requireAuth,
      permissions: perms,
      anyPermission: anyPerm,
      roles: roles,
      isPublic: isPublic,
    );
  }

  Set<String> _readStringSet(DartObject value, String field) {
    final v = value.getField(field);
    if (v == null) return const <String>{};
    final set = v.toSetValue();
    if (set != null) {
      return set.map((d) => d.toStringValue()).whereType<String>().toSet();
    }
    final list = v.toListValue();
    if (list != null) {
      return list.map((d) => d.toStringValue()).whereType<String>().toSet();
    }
    return const <String>{};
  }

  List<String> _readMiddlewareNames(List<ElementAnnotation> metadata) {
    final names = <String>[];
    for (final m in metadata) {
      final value = m.computeConstantValue();
      if (value == null) continue;
      final type = value.type;
      final element = type?.element;
      if (element is! ClassElement) continue;
      if (element.name != 'UseMiddleware') continue;
      if (!element.library.identifier.contains('gisila')) continue;
      final name = value.getField('name')?.toStringValue();
      if (name != null && name.isNotEmpty) names.add(name);
    }
    return names;
  }

  _Guards _mergeGuards(_Guards a, _Guards b) {
    return _Guards(
      requireAuth: a.requireAuth || b.requireAuth,
      permissions: {...a.permissions, ...b.permissions},
      anyPermission: {...a.anyPermission, ...b.anyPermission},
      roles: {...a.roles, ...b.roles},
      isPublic: false,
    );
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

      if (isShelfRequest(p.type)) {
        infos.add(_ParamInfo(
          parameter: p,
          source: _Source.request,
          openApiName: p.name,
        ));
        continue;
      }

      if (isRequestContext(p.type)) {
        infos.add(_ParamInfo(
          parameter: p,
          source: _Source.context,
          openApiName: p.name,
        ));
        continue;
      }

      if (isFormSubtype(p.type)) {
        infos.add(_ParamInfo(
          parameter: p,
          source: _Source.form,
          openApiName: p.name,
        ));
        bodySeen = true;
        continue;
      }

      if (isServiceSubtype(p.type)) {
        infos.add(_ParamInfo(
          parameter: p,
          source: _Source.service,
          openApiName: p.name,
        ));
        continue;
      }

      if (placeholders.contains(p.name)) {
        infos.add(_ParamInfo(
          parameter: p,
          source: _Source.path,
          openApiName: p.name,
        ));
        continue;
      }

      if (isCoercible(p.type)) {
        infos.add(_ParamInfo(
          parameter: p,
          source: _Source.query,
          openApiName: p.name,
        ));
        continue;
      }

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
      if (type.isDartCoreMap) {
        return (raw) => '($raw as Map).cast<String, dynamic>()';
      }
    }

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

String _dartStr(String value) => gisila_builder.dartString(value);

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
    this.config,
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
  final DartType? returnsBodyType;
  final _BodyDocMeta? bodyDoc;
  final List<_QueryDocMeta> extraQueryDocs;
  final DartObject? config;
}

class _ExtraResponse {
  _ExtraResponse({
    required this.statusCode,
    this.description,
    this.bodyType,
  });
  final int statusCode;
  final String? description;
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

class _Guards {
  const _Guards({
    required this.requireAuth,
    required this.permissions,
    required this.anyPermission,
    required this.roles,
    required this.isPublic,
  });

  const _Guards.public()
      : requireAuth = false,
        permissions = const <String>{},
        anyPermission = const <String>{},
        roles = const <String>{},
        isPublic = true;

  final bool requireAuth;
  final Set<String> permissions;
  final Set<String> anyPermission;
  final Set<String> roles;
  final bool isPublic;
}
