// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'users_controller.dart';

// **************************************************************************
// ControllerGenerator
// **************************************************************************

// **************************************************
// gisila_doc: generated for UsersController
// **************************************************

extension UsersControllerOpenApi on UsersController {
  /// Registers every annotated route of this controller on
  /// [router] and contributes the operations to [spec].
  ///
  /// Pass [prefix] to mount the controller under an extra
  /// path segment (e.g. an `/api/v1` versioning prefix).
  void attachOpenApi(
    OpenApiSpec spec,
    Router router, {
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
    spec.putSchema('CreateUser', <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'name': <String, Object?>{'type': 'string'},
        'email': <String, Object?>{'type': 'string'},
        'age': <String, Object?>{
          'type': <Object?>['integer', 'null'],
          'format': 'int64'
        }
      },
      'required': <String>['name', 'email']
    });
    spec.putTag('Users');
    {
      final basePath = '$prefix/users/';
      final openApiPath = '$prefix/users/';
      router.get(basePath, (Request request) async {
        try {
          final limit = coerce<int?>(
              request.url.queryParameters['limit'], 'limit',
              required: false);
          final offset = coerce<int?>(
              request.url.queryParameters['offset'], 'offset',
              required: false);
          final result = await this.listUsers(limit: limit, offset: offset);
          return jsonResponse(result, statusCode: 200);
        } on BadRequestException catch (e) {
          return Response(400,
              body: '{"error":"${e.message}"}',
              headers: const {'content-type': 'application/json'});
        } on TypeError catch (e) {
          return Response(400,
              body: '{"error":"Invalid request payload ($e)"}',
              headers: const {'content-type': 'application/json'});
        } on FormatException catch (e) {
          return Response(400,
              body: '{"error":"Invalid request format: ${e.message}"}',
              headers: const {'content-type': 'application/json'});
        }
      });
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
              })
            },
          ));
    }
    {
      final basePath = '$prefix/users/<id>';
      final openApiPath = '$prefix/users/{id}';
      router.get(basePath, (Request request) async {
        try {
          final id = coerce<String>(request.params['id'], 'id', required: true);
          final response = await this.getUser(id);
          return response;
        } on BadRequestException catch (e) {
          return Response(400,
              body: '{"error":"${e.message}"}',
              headers: const {'content-type': 'application/json'});
        } on TypeError catch (e) {
          return Response(400,
              body: '{"error":"Invalid request payload ($e)"}',
              headers: const {'content-type': 'application/json'});
        } on FormatException catch (e) {
          return Response(400,
              body: '{"error":"Invalid request format: ${e.message}"}',
              headers: const {'content-type': 'application/json'});
        }
      });
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
              '200': ResponseSpec(description: 'OK'),
              '404': ResponseSpec(description: 'User not found')
            },
          ));
    }
    {
      final basePath = '$prefix/users/';
      final openApiPath = '$prefix/users/';
      router.post(basePath, (Request request) async {
        try {
          final __raw_body = await readJsonBody(request, required: true);
          final body = CreateUser.fromJson(__raw_body as Map<String, dynamic>);
          final result = await this.createUser(body);
          return jsonResponse(result, statusCode: 201);
        } on BadRequestException catch (e) {
          return Response(400,
              body: '{"error":"${e.message}"}',
              headers: const {'content-type': 'application/json'});
        } on TypeError catch (e) {
          return Response(400,
              body: '{"error":"Invalid request payload ($e)"}',
              headers: const {'content-type': 'application/json'});
        } on FormatException catch (e) {
          return Response(400,
              body: '{"error":"Invalid request format: ${e.message}"}',
              headers: const {'content-type': 'application/json'});
        }
      });
      spec.putOperation(
          openApiPath,
          'post',
          Operation(
            summary: 'Create a user',
            tags: <String>['Users'],
            parameters: <Parameter>[],
            requestBody: RequestBody(required: true, content: {
              'application/json': MediaType(schema: <String, Object?>{
                r'$ref': '#/components/schemas/CreateUser'
              })
            }),
            responses: <String, ResponseSpec>{
              '201': ResponseSpec(description: 'Created', content: {
                'application/json': MediaType(schema: <String, Object?>{
                  r'$ref': '#/components/schemas/User'
                })
              })
            },
          ));
    }
    {
      final basePath = '$prefix/users/<id>';
      final openApiPath = '$prefix/users/{id}';
      router.delete(basePath, (Request request) async {
        try {
          final id = coerce<String>(request.params['id'], 'id', required: true);
          await this.deleteUser(id);
          return emptyResponse(statusCode: 204);
        } on BadRequestException catch (e) {
          return Response(400,
              body: '{"error":"${e.message}"}',
              headers: const {'content-type': 'application/json'});
        } on TypeError catch (e) {
          return Response(400,
              body: '{"error":"Invalid request payload ($e)"}',
              headers: const {'content-type': 'application/json'});
        } on FormatException catch (e) {
          return Response(400,
              body: '{"error":"Invalid request format: ${e.message}"}',
              headers: const {'content-type': 'application/json'});
        }
      });
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
              '204': ResponseSpec(description: 'No Content')
            },
          ));
    }
  }
}
