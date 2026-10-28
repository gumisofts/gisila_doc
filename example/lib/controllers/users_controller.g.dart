// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'users_controller.dart';

// **************************************************************************
// ControllerGenerator
// **************************************************************************

// **************************************************
// gisila_doc: generated for UsersController
// **************************************************

extension UsersControllerGisilaDoc on UsersController {
  /// Registers every annotated route of this controller on
  /// [router] (through `gisilaRoute(...)` so the route runs
  /// through the same MVC pipeline as gisila core) and
  /// contributes the matching operations / schemas / tags
  /// to [spec].
  ///
  /// Pass [prefix] to mount the controller under an extra
  /// path segment (e.g. an `/api/v1` versioning prefix).
  void attachToApp(
    GisilaApp app,
    Router router,
    OpenApiSpec spec, {
    String prefix = '',
  }) {
    spec.putSchema('User', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'id': <String, Object?>{'type': 'string'},
        'name': <String, Object?>{'type': 'string'},
        'email': <String, Object?>{'type': 'string'},
        'age': <String, Object?>{
          'type': <Object?>['integer', 'null'],
          'format': 'int64'
        },
        'createdAt': <String, Object?>{
          'type': <Object?>['string', 'null'],
          'format': 'date-time'
        }
      },
      'required': <String>['id', 'name', 'email']
    });
    spec.putSchema('CreateUserForm', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'name': <String, Object?>{'type': 'string'},
        'email': <String, Object?>{'type': 'string', 'format': 'email'},
        'age': <String, Object?>{'type': 'integer', 'format': 'int64'}
      }
    });
    spec.putTag('Users');
    {
      final basePath = '$prefix/users/';
      final openApiPath = '$prefix/users/';
      final RouteConfig __cfg = RouteConfig.empty;
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (users, limit, offset) = await (() async {
            try {
              final users = ctx.service<UserService>();
              final limit = coerce<int?>(
                  request.url.queryParameters['limit'], 'limit',
                  required: false);
              final offset = coerce<int?>(
                  request.url.queryParameters['offset'], 'offset',
                  required: false);
              return (users, limit, offset);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result =
              await this.listUsers(users, limit: limit, offset: offset);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.get(basePath, __route);
      if (basePath.length > 1) {
        router.get(basePath.substring(0, basePath.length - 1), __route);
      }
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'List users',
            description: 'Returns a (paginated) list of all known users.',
            tags: <String>['Users'],
            parameters: <Parameter>[
              Parameter(
                name: 'limit',
                location: 'query',
                required: false,
                description: null,
                schema: <String, Object?>{
                  'type': <Object?>['integer', 'null'],
                  'format': 'int64'
                },
              ),
              Parameter(
                name: 'offset',
                location: 'query',
                required: false,
                description: null,
                schema: <String, Object?>{
                  'type': <Object?>['integer', 'null'],
                  'format': 'int64'
                },
              )
            ],
            responses: <String, ResponseSpec>{
              '200': ResponseSpec(description: 'OK', content: {
                'application/json': MediaType(schema: <String, Object?>{
                  'type': 'array',
                  'items': <String, Object?>{
                    r'$ref': '#/components/schemas/User'
                  }
                })
              }),
              '400': ResponseSpec(description: 'Bad Request', content: {
                'application/json': MediaType(schema: errorEnvelopeSchema)
              })
            },
          ));
    }
    {
      final basePath = '$prefix/users/<id>';
      final openApiPath = '$prefix/users/{id}';
      final RouteConfig __cfg = RouteConfig.empty;
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'GET $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, users) = await (() async {
            try {
              final id =
                  coerce<String>(request.params['id'], 'id', required: true);
              final users = ctx.service<UserService>();
              return (id, users);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.getUser(id, users);
          return jsonResponse(body: result, statusCode: 200);
        },
      );
      router.get(basePath, __route);
      spec.putOperation(
          openApiPath,
          'get',
          Operation(
            summary: 'Fetch a user',
            operationId: 'getUserById',
            tags: <String>['Users'],
            parameters: <Parameter>[
              Parameter(
                name: 'id',
                location: 'path',
                required: true,
                description: null,
                schema: <String, Object?>{'type': 'string'},
              )
            ],
            responses: <String, ResponseSpec>{
              '200': ResponseSpec(description: 'OK', content: {
                'application/json': MediaType(schema: <String, Object?>{
                  r'$ref': '#/components/schemas/User'
                })
              }),
              '404': ResponseSpec(description: 'User not found'),
              '400': ResponseSpec(description: 'Bad Request', content: {
                'application/json': MediaType(schema: errorEnvelopeSchema)
              })
            },
          ));
    }
    {
      final basePath = '$prefix/users/';
      final openApiPath = '$prefix/users/';
      final RouteConfig __cfg = RouteConfig.empty.merge(const RouteConfig(
          rateLimit: const RateLimitConfig(requestsPerMinute: 60)));
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'POST $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (form, users) = await (() async {
            try {
              final form = await bindForm(request, CreateUserForm.new);
              final users = ctx.service<UserService>();
              return (form, users);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          final result = await this.createUser(form, users);
          return jsonResponse(body: result, statusCode: 201);
        },
      );
      router.post(basePath, __route);
      if (basePath.length > 1) {
        router.post(basePath.substring(0, basePath.length - 1), __route);
      }
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Create a user',
            tags: <String>['Users'],
            parameters: <Parameter>[],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/CreateUserForm'
              }),
              'application/x-www-form-urlencoded': MediaType(
                  schema: <String, Object?>{
                    r'$ref': '#/components/schemas/CreateUserForm'
                  })
            }),
            responses: <String, ResponseSpec>{
              '201': ResponseSpec(description: 'Created', content: {
                'application/json': MediaType(schema: <String, Object?>{
                  r'$ref': '#/components/schemas/User'
                })
              }),
              '400': ResponseSpec(description: 'Bad Request', content: {
                'application/json': MediaType(schema: errorEnvelopeSchema)
              })
            },
          ));
    }
    {
      final basePath = '$prefix/users/<id>';
      final openApiPath = '$prefix/users/{id}';
      final RouteConfig __cfg = RouteConfig.empty;
      final __route = gisilaRoute(
        app: app,
        config: __cfg,
        routeId: 'DELETE $basePath',
        handler: (RequestContext ctx) async {
          final request = ctx.request;
          final (id, users) = await (() async {
            try {
              final id =
                  coerce<String>(request.params['id'], 'id', required: true);
              final users = ctx.service<UserService>();
              return (id, users);
            } on TypeError catch (e) {
              throw BadRequestException('Invalid request payload ($e)');
            } on FormatException catch (e) {
              throw BadRequestException('Invalid request format: ${e.message}');
            }
          })();
          await this.deleteUser(id, users);
          return emptyResponse(statusCode: 204);
        },
      );
      router.delete(basePath, __route);
      spec.putOperation(
          openApiPath,
          'delete',
          Operation(
            summary: 'Delete a user',
            tags: <String>['Users'],
            parameters: <Parameter>[
              Parameter(
                name: 'id',
                location: 'path',
                required: true,
                description: null,
                schema: <String, Object?>{'type': 'string'},
              )
            ],
            responses: <String, ResponseSpec>{
              '204': ResponseSpec(description: 'No Content'),
              '400': ResponseSpec(description: 'Bad Request', content: {
                'application/json': MediaType(schema: errorEnvelopeSchema)
              })
            },
          ));
    }
  }
}
