/// Arquivo: config_classifier_test.dart
/// Módulo: pillar_web_sw / testes
/// Descrição: Unit tests for web_sw.yaml parsing, classification and the
///   deterministic JSON table.
/// Dependências: package:test, support.dart.
/// Premissas: precedence ignore > onDemand > core.
/// Edge Cases: unknown keys, wrong types, unmatched entries.
library;

import 'dart:convert';

import 'package:pillar_web_sw/pillar_web_sw.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('WebSwConfig.parse', () {
    test('reads every key', () {
      final c = WebSwConfig.parse('''
cachePrefix: bible
core: [index.html, "*.js"]
onDemand: ["assets/bible/**"]
ignore: ["**/*.txt"]
neverIntercept: [/api/, /auth/]
navigationFallback: false
''');
      expect(c.cachePrefix, 'bible');
      expect(c.core, ['index.html', '*.js']);
      expect(c.onDemand, ['assets/bible/**']);
      expect(c.ignore, ['**/*.txt']);
      expect(c.neverIntercept, ['/api/', '/auth/']);
      expect(c.navigationFallback, isFalse);
    });

    test('empty file gives defaults', () {
      final c = WebSwConfig.parse('');
      expect(c.cachePrefix, 'app');
      expect(c.core, ['**']);
      expect(c.navigationFallback, isTrue);
    });

    test('rejects unknown keys, wrong types and bad prefix', () {
      expect(
        () => WebSwConfig.parse('cache: x'),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => WebSwConfig.parse('core: x'),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => WebSwConfig.parse('navigationFallback: 1'),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => WebSwConfig.parse('cachePrefix: "a b"'),
        throwsA(isA<ConfigException>()),
      );
      expect(() => WebSwConfig.parse('- a'), throwsA(isA<ConfigException>()));
    });
  });

  group('classify', () {
    late List<ManifestEntry> entries;
    setUp(() => entries = scanBuild(fixture(baseBuild())));

    test('default config puts everything in the core', () {
      final c = classify(entries, const WebSwConfig());
      expect(c.core, hasLength(entries.length));
      expect(c.onDemand, isEmpty);
    });

    test('on-demand beats core and ignore beats both', () {
      const config = WebSwConfig(
        onDemand: ['assets/bible/**'],
        ignore: ['version.json', 'assets/bible/nvi.*'],
      );
      final c = classify(entries, config);
      expect(
        c.ignored.map((e) => e.url),
        containsAll(['version.json', 'assets/bible/nvi.2a2a2a2a.json']),
      );
      expect(c.onDemand, isEmpty);
    });

    test('entries matching no list are ignored', () {
      final c = classify(entries, const WebSwConfig(core: ['index.html']));
      expect(c.core.map((e) => e.url), ['index.html']);
      expect(c.ignored, hasLength(entries.length - 1));
    });
  });

  group('table', () {
    test('is deterministic and carries strategies', () {
      const config = WebSwConfig(
        cachePrefix: 'bible',
        onDemand: ['assets/bible/**'],
        neverIntercept: ['/b/', '/a/'],
      );
      String render() {
        final e = scanBuild(fixture(baseBuild()));
        final c = classify(e, config);
        return encodeTable(
          buildTable(
            classification: c,
            config: config,
            releaseId: computeReleaseId(c.core),
          ),
        );
      }

      final first = render();
      expect(render(), first);
      final json = jsonDecode(first) as Map<String, dynamic>;
      expect(json['cachePrefix'], 'bible');
      expect(json['neverIntercept'], ['/a/', '/b/']);
      final core = (json['core'] as List).cast<Map<String, dynamic>>();
      expect(core.every((e) => e['strategy'] == 'release-cache-first'), isTrue);
      final od = (json['onDemand'] as List).cast<Map<String, dynamic>>();
      expect(od.single['url'], 'assets/bible/nvi.2a2a2a2a.json');
      expect(od.single['strategy'], 'on-demand');
      expect(od.single['urlHashed'], isTrue);
    });
  });
}
