/// Arquivo: worker_js_test.dart
/// Módulo: pillar_web_sw / testes
/// Descrição: Integration test: generates the worker for a fixture build and
///   runs it in a Node harness with mocked caches/fetch/self (one Dart test
///   per JS scenario), plus `node --check` on every generated file.
/// Dependências: package:test, Node 18+ on PATH (optional), test/js/.
/// Premissas: Node is a dev-time tool only, never a package dependency.
///   Without Node the JS tests are skipped with a message saying so.
/// Edge Cases: the harness runs once; the scenario names come from it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support.dart';

final bool hasNode = _nodeVersion() != null;

String? _nodeVersion() {
  try {
    final r = Process.runSync('node', ['--version']);
    return r.exitCode == 0 ? (r.stdout as String).trim() : null;
  } on ProcessException {
    return null;
  }
}

const _files = {
  'index.html': '<html>index</html>',
  'flutter.js': 'flutter loader',
  'flutter_bootstrap.js': 'bootstrap',
  'main.dart.js': 'main',
  'version.json': '{}',
  'config.js': 'window.cfg = 1;',
  'assets/AssetManifest.bin': 'bin',
  'assets/fonts/Roboto.1a2b3c4d.ttf': 'font',
  'assets/bible/nvi.2a2a2a2a.json': 'big bible',
  'icons/Icon-192.png': 'png',
};

/// Writes the fixture build under [parent] and runs the generator on it.
Directory makeBuild(Directory parent, String name, {bool kill = false}) {
  final dir = Directory('${parent.path}/$name')..createSync();
  _files.forEach((url, text) {
    File('${dir.path}/$url')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  });
  final cfg = File('${parent.path}/$name.yaml')
    ..writeAsStringSync(
      'onDemand: ["assets/bible/**"]\n'
      'neverIntercept: ["/api/"]\n'
      'noHashCheck: ["assets/AssetManifest.bin"]\n',
    );
  final (code, _, err) = cli([
    dir.path,
    '--config',
    cfg.path,
    if (kill) '--kill-switch',
  ]);
  if (code != 0) throw StateError('generator failed: $err');
  return dir;
}

void main() {
  const skip = 'node não encontrado: comportamento JS NÃO EXECUTADO';
  final harness = File('test/js/worker_scenarios.js').absolute.path;
  final root = Directory.systemTemp.createTempSync('pws_js_');
  tearDownAll(() => root.deleteSync(recursive: true));
  final worker = makeBuild(root, 'w');
  final kill = makeBuild(root, 'k', kill: true);

  test('generated JS files pass node --check', () {
    final files = [
      '${worker.path}/app-service-worker.js',
      '${worker.path}/app-sw-register.js',
      '${kill.path}/app-service-worker.js',
    ];
    for (final f in files) {
      final r = Process.runSync('node', ['--check', f]);
      expect(r.exitCode, 0, reason: '$f: ${r.stderr}');
    }
  }, skip: hasNode ? false : skip);

  if (!hasNode) {
    test('worker behavior in the JS harness', () {}, skip: skip);
    return;
  }

  final run = Process.runSync('node', [harness, worker.path, kill.path]);
  final results = run.exitCode == 0
      ? (jsonDecode(run.stdout as String) as List).cast<Map<String, dynamic>>()
      : <Map<String, dynamic>>[];

  test('the harness runs', () {
    expect(run.exitCode, 0, reason: '${run.stderr}');
  });
  for (final r in results) {
    test('JS: ${r['name']}', () {
      expect(r['ok'], isTrue, reason: '${r['error']}');
    });
  }
}
