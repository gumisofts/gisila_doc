import 'dart:convert';

import 'package:gisila_doc/gisila_doc.dart';
import 'package:test/test.dart';

void main() {
  group('OpenApiSpec', () {
    test('emits a minimal valid 3.1.0 document', () {
      final spec = OpenApiSpec(
        info: const ApiInfo(title: 'T', version: '1.0.0'),
      );

      final json = jsonDecode(spec.toJson()) as Map<String, dynamic>;
      expect(json['openapi'], '3.1.0');
      expect(json['info'], {'title': 'T', 'version': '1.0.0'});
      expect(json['paths'], isEmpty);
      expect(json.containsKey('components'), isFalse);
    });

    test('preserves operation insertion order across paths and methods', () {
      final spec = OpenApiSpec(info: const ApiInfo(title: 'T', version: '1'));

      spec.putOperation(
        '/users',
        'get',
        Operation(responses: const {
          '200': ResponseSpec(description: 'ok'),
        }),
      );
      spec.putOperation(
        '/users',
        'post',
        Operation(responses: const {
          '201': ResponseSpec(description: 'created'),
        }),
      );
      spec.putOperation(
        '/items',
        'get',
        Operation(responses: const {
          '200': ResponseSpec(description: 'ok'),
        }),
      );

      final json = jsonDecode(spec.toJson()) as Map<String, dynamic>;
      final paths = json['paths'] as Map<String, dynamic>;
      expect(paths.keys.toList(), ['/users', '/items']);
      expect(
        (paths['/users'] as Map<String, dynamic>).keys.toList(),
        ['get', 'post'],
      );
    });

    test('component schemas appear under components.schemas exactly once', () {
      final spec = OpenApiSpec(info: const ApiInfo(title: 'T', version: '1'));
      spec.putSchema('User', {'type': 'object'});
      // Repeat - first one wins, no duplicate.
      spec.putSchema('User', {'type': 'string'});

      final json = jsonDecode(spec.toJson()) as Map<String, dynamic>;
      expect(json['components'], {
        'schemas': {
          'User': {'type': 'object'},
        }
      });
    });
  });

  group('coerce', () {
    test('returns null when not required and value is missing', () {
      expect(coerce<int?>(null, 'x', required: false), isNull);
      expect(coerce<String?>('', 'x', required: false), isNull);
    });

    test('throws BadRequestException when required value is missing', () {
      expect(
        () => coerce<int>(null, 'x', required: true),
        throwsA(isA<BadRequestException>()),
      );
    });

    test('coerces integers, doubles, bools and dates', () {
      expect(coerce<int>('7', 'x', required: true), 7);
      expect(coerce<double>('3.14', 'x', required: true), 3.14);
      expect(coerce<bool>('true', 'x', required: true), isTrue);
      expect(coerce<bool>('no', 'x', required: true), isFalse);
      final d = coerce<DateTime>('2024-01-02T03:04:05Z', 'x', required: true);
      expect(d.toUtc().hour, 3);
    });

    test('throws for malformed primitives', () {
      expect(() => coerce<int>('abc', 'x', required: true),
          throwsA(isA<BadRequestException>()));
      expect(() => coerce<bool>('maybe', 'x', required: true),
          throwsA(isA<BadRequestException>()));
    });
  });
}
