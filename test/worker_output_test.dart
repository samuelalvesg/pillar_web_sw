/// Arquivo: worker_output_test.dart
/// Módulo: pillar_web_sw / testes
/// Descrição: Unit and integration tests of the files the generator writes:
///   determinism, embedded table, kill switch, flag conflicts, no writes
///   with --check-only / --print-table.
/// Dependências: package:test, support.dart.
/// Premissas: pure Dart, no Node needed (the JS behavior is in
///   worker_js_test.dart).
/// Edge Cases: stale generated files from a previous run are overwritten and
///   never enter the table.
library;

import 'dart:convert';
import 'dart:io';

import 'package:pillar_web_sw/pillar_web_sw.dart';
import 'package:test/test.dart';

import 'support.dart';

String read(Directory d, String name) =>
    File('${d.path}/$name').readAsStringSync();

Map<String, dynamic> embeddedTable(String worker) {
  final m = RegExp(r'const TABLE = (\{[\s\S]*?\n\});').firstMatch(worker)!;
  return jsonDecode(m.group(1)!) as Map<String, dynamic>;
}

void main() {
  test('writes the worker and the register script into the build', () {
    final dir = fixture(baseBuild());
    final (code, out, _) = cli([dir.path]);
    expect(code, 0);
    expect(out, contains('app-service-worker.js'));
    expect(read(dir, 'app-service-worker.js'), isNot('old'));
    expect(read(dir, 'app-sw-register.js'), contains('updateViaCache'));
  });

  test('the worker embeds the table and the release id', () {
    final dir = fixture(baseBuild());
    cli([dir.path, '--release-id', 'r9']);
    final table = embeddedTable(read(dir, 'app-service-worker.js'));
    expect(table['releaseId'], 'r9');
    expect(
      (table['core'] as List).map((e) => (e as Map)['url']),
      contains('main.dart.js'),
    );
    expect(
      (table['core'] as List).map((e) => (e as Map)['url']),
      isNot(contains('app-service-worker.js')),
    );
    final printed = jsonDecode(
      cli([dir.path, '--print-table', '--release-id', 'r9']).$2,
    );
    expect(table, printed);
  });

  test('same input gives the same bytes, even when run twice in place', () {
    final dir = fixture(baseBuild());
    cli([dir.path]);
    final first = [
      read(dir, 'app-service-worker.js'),
      read(dir, 'app-sw-register.js'),
    ];
    cli([dir.path]);
    expect(read(dir, 'app-service-worker.js'), first[0]);
    expect(read(dir, 'app-sw-register.js'), first[1]);
    final other = fixture(baseBuild());
    cli([other.path]);
    expect(read(other, 'app-service-worker.js'), first[0]);
  });

  test('the release id covers the worker model, not just the core', () {
    final core = scanBuild(fixture(baseBuild()));
    final ids = {
      computeReleaseId(core),
      computeReleaseId(core, model: 'aaaaaaaa'),
      computeReleaseId(core, model: 'bbbbbbbb'),
    };
    expect(ids, hasLength(3));
    expect(
      computeReleaseId(core, model: 'aaaaaaaa'),
      computeReleaseId(core, model: 'aaaaaaaa'),
    );
    expect(workerModelId, matches(RegExp(r'^[0-9a-f]{8}$')));
    final dir = fixture(baseBuild());
    cli([dir.path]);
    final table = embeddedTable(read(dir, 'app-service-worker.js'));
    final scanned = classify(scanBuild(dir), const WebSwConfig()).core;
    expect(table['releaseId'], computeReleaseId(scanned, model: workerModelId));
  });

  test('--release-id still wins over the computed id', () {
    final dir = fixture(baseBuild());
    cli([dir.path, '--release-id', 'manual1']);
    expect(
      embeddedTable(read(dir, 'app-service-worker.js'))['releaseId'],
      'manual1',
    );
  });

  test('different content gives a different worker', () {
    final a = fixture(baseBuild());
    final b = fixture({...baseBuild(), 'main.dart.js': 'changed'});
    cli([a.path]);
    cli([b.path]);
    expect(
      read(a, 'app-service-worker.js'),
      isNot(read(b, 'app-service-worker.js')),
    );
  });

  test('--check-only and --print-table write nothing', () {
    final dir = fixture(baseBuild());
    cli([dir.path, '--check-only']);
    cli([dir.path, '--print-table']);
    expect(read(dir, 'app-service-worker.js'), 'old');
    expect(read(dir, 'app-sw-register.js'), 'old');
  });

  test('a divergent manifest writes nothing and exits 1', () {
    final dir = fixture(baseBuild());
    writeManifest(dir, [
      {
        'url': 'assets/bible/nvi.2a2a2a2a.json',
        'hash': 'ffffffff',
        'size': 3,
        'urlHashed': true,
      },
    ]);
    expect(cli([dir.path]).$1, 1);
    expect(read(dir, 'app-service-worker.js'), 'old');
  });

  test('a url with a dollar sign or the token cannot corrupt the worker', () {
    final dir = fixture({
      ...baseBuild(),
      r'assets/a$1.txt': 'x',
      'assets/__APP_SW_TABLE__.txt': 'y',
    });
    expect(cli([dir.path]).$1, 0);
    final table = embeddedTable(read(dir, 'app-service-worker.js'));
    expect(
      (table['core'] as List).map((e) => (e as Map)['url']),
      containsAll([r'assets/a$1.txt', 'assets/__APP_SW_TABLE__.txt']),
    );
  });

  test('--kill-switch writes a cache-wiping worker under the same name', () {
    final dir = fixture(baseBuild());
    final cfg = File('${dir.path}/../kill_${dir.hashCode}.yaml')
      ..writeAsStringSync('cachePrefix: bible');
    addTearDown(cfg.deleteSync);
    final (code, _, _) = cli([dir.path, '--kill-switch', '--config', cfg.path]);
    expect(code, 0);
    final text = read(dir, 'app-service-worker.js');
    expect(text, contains('const PREFIX = "bible";'));
    expect(text, contains('unregister()'));
    expect(text, isNot(contains("addEventListener('fetch'")));
    expect(read(dir, 'app-sw-register.js'), 'old');
    expect(renderKillSwitch('bible'), text);
  });

  test('--kill-switch with --check-only or --print-table is a usage error', () {
    final dir = fixture(baseBuild());
    expect(cli([dir.path, '--kill-switch', '--check-only']).$1, 2);
    expect(cli([dir.path, '--kill-switch', '--print-table']).$1, 2);
    expect(read(dir, 'app-service-worker.js'), 'old');
  });

  test('the worker text honors the ADR contract', () {
    final text = renderWorker({
      'cachePrefix': 'app',
      'releaseId': 'abc',
      'navigationFallback': true,
      'neverIntercept': <String>[],
      'core': <Object>[],
      'onDemand': <Object>[],
      'ignored': <Object>[],
    });
    expect(text, isNot(contains('__APP_SW_TABLE__')));
    for (final needle in [
      "cache: 'reload'",
      'crypto.subtle',
      'app-sw-skip-waiting',
      'app-sw-status',
      'flutter-app-cache',
      'flutter-temp-cache',
      'flutter-app-manifest',
      'fonts.gstatic.com',
      '/flutter-canvaskit/',
    ]) {
      expect(text, contains(needle), reason: needle);
    }
    // No unconditional skipWaiting at install.
    expect(
      RegExp(r"'install'[\s\S]{0,200}skipWaiting").hasMatch(text),
      isFalse,
    );
  });
}
