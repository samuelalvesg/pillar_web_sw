/// Arquivo: scanner_test.dart
/// Módulo: pillar_web_sw / testes
/// Descrição: Unit tests for the disk scan, exclusions, urlHashed rule,
///   manifest cross-check and release_id.
/// Dependências: package:test, support.dart.
/// Premissas: fixtures live in temp dirs.
/// Edge Cases: absent and malformed manifests.
library;

import 'dart:io';

import 'package:pillar_web_sw/pillar_web_sw.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('scanBuild', () {
    test('keeps only cacheable files, sorted, in manifest format', () {
      final entries = scanBuild(fixture(baseBuild()));
      expect(entries.map((e) => e.url), [
        'assets/AssetManifest.bin',
        'assets/bible/nvi.2a2a2a2a.json',
        'flutter.js',
        'flutter_bootstrap.js',
        'index.html',
        'main.dart.js',
        'manifest.json',
        'version.json',
      ]);
    });

    test('hash is 8 hex of SHA-256 and size is the byte length', () {
      final dir = fixture({'a.txt': 'abc'});
      final e = scanBuild(dir).single;
      expect(e.hash, 'ba7816bf');
      expect(e.size, 3);
    });

    test('excludes dotfiles in nested folders and canvaskit/**', () {
      final dir = fixture({
        'index.html': 'i',
        'assets/.hidden': 'h',
        '.dir/file.js': 'f',
        'canvaskit/chromium/canvaskit.js': 'c',
      });
      expect(scanBuild(dir).map((e) => e.url), ['index.html']);
    });

    test('urlHashed follows the SDK rule', () {
      expect(isUrlHashed('main.dart.0a1b2c3d.wasm'), isTrue);
      expect(isUrlHashed('assets/x/font.ffffffff.otf'), isTrue);
      expect(isUrlHashed('main.dart.js'), isFalse);
      expect(isUrlHashed('main.0a1b2c3.js'), isFalse);
      expect(isUrlHashed('main.0A1B2C3D.js'), isFalse);
      expect(isUrlHashed('dir.0a1b2c3d/main.js'), isFalse);
    });
  });

  group('checkAgainstManifest', () {
    test('absent manifest is not an error', () {
      final dir = fixture(baseBuild());
      expect(checkAgainstManifest(dir, scanBuild(dir)), isEmpty);
    });

    test('matching urlHashed entries pass', () {
      final dir = fixture(baseBuild());
      final hashed = scanBuild(dir).firstWhere((e) => e.urlHashed);
      writeManifest(dir, [hashed.toJson()]);
      expect(checkAgainstManifest(dir, scanBuild(dir)), isEmpty);
    });

    test('divergent urlHashed hash is reported by file name', () {
      final dir = fixture(baseBuild());
      writeManifest(dir, [
        {
          'url': 'assets/bible/nvi.2a2a2a2a.json',
          'hash': '00000000',
          'size': 3,
          'urlHashed': true,
        },
      ]);
      final problems = checkAgainstManifest(dir, scanBuild(dir));
      expect(problems.single, contains('assets/bible/nvi.2a2a2a2a.json'));
    });

    test('non-urlHashed entries are not compared', () {
      final dir = fixture(baseBuild());
      writeManifest(dir, [
        {
          'url': 'index.html',
          'hash': '00000000',
          'size': 1,
          'urlHashed': false,
        },
      ]);
      expect(checkAgainstManifest(dir, scanBuild(dir)), isEmpty);
    });

    test('urlHashed entry missing from disk is reported', () {
      final dir = fixture(baseBuild());
      writeManifest(dir, [
        {
          'url': '/gone.0a0a0a0a.js',
          'hash': '0a0a0a0a',
          'size': 1,
          'urlHashed': true,
        },
      ]);
      expect(
        checkAgainstManifest(dir, scanBuild(dir)).single,
        contains('gone.0a0a0a0a.js'),
      );
    });

    test('malformed manifest is a divergence, not a crash', () {
      final dir = fixture(baseBuild());
      File('${dir.path}/precache_manifest.json').writeAsStringSync('{oops');
      expect(checkAgainstManifest(dir, scanBuild(dir)), hasLength(1));
    });
  });

  group('release id', () {
    String idOf(Map<String, String> files) {
      final entries = scanBuild(fixture(files));
      return computeReleaseId(classify(entries, const WebSwConfig()).core);
    }

    test('same content gives same id regardless of creation order', () {
      final a = idOf({'a.js': '1', 'b.js': '2'});
      final b = idOf({'b.js': '2', 'a.js': '1'});
      expect(a, b);
      expect(a, matches(RegExp(r'^[0-9a-f]{8}$')));
    });

    test('a changed byte changes the id', () {
      expect(idOf({'a.js': '1'}), isNot(idOf({'a.js': '2'})));
    });

    test('on-demand content does not change the id', () {
      const config = WebSwConfig(core: ['*.js'], onDemand: ['*.json']);
      String id(String json) {
        final e = scanBuild(fixture({'a.js': '1', 'b.json': json}));
        return computeReleaseId(classify(e, config).core);
      }

      expect(id('x'), id('y'));
    });
  });
}
