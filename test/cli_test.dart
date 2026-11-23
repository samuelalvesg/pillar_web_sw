/// Arquivo: cli_test.dart
/// Módulo: pillar_web_sw / testes
/// Descrição: Integration tests of the command: in-process exit codes and
///   one real `dart run` of the executable.
/// Dependências: package:test, support.dart.
/// Premissas: exit 0 ok, 1 divergence, 2 usage.
/// Edge Cases: missing dir, bad flags, bad config, release-id override.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('ok build exits 0 with a summary', () {
    final dir = fixture(baseBuild());
    final (code, out, _) = cli([dir.path]);
    expect(code, 0);
    expect(out, contains('release_id'));
    expect(out, contains('8 no núcleo'));
  });

  test('--print-table prints the JSON table, --release-id overrides', () {
    final dir = fixture(baseBuild());
    final (code, out, _) = cli([
      dir.path,
      '--print-table',
      '--release-id',
      'r1',
    ]);
    expect(code, 0);
    expect((jsonDecode(out) as Map)['releaseId'], 'r1');
  });

  test('--config is applied', () {
    final dir = fixture(baseBuild());
    final cfg = File(
      '${dir.path}/../${dir.uri.pathSegments[dir.uri.pathSegments.length - 2]}.yaml',
    )..writeAsStringSync('cachePrefix: zz\ncore: [index.html]');
    addTearDown(cfg.deleteSync);
    final (code, out, _) = cli([
      dir.path,
      '--print-table',
      '--config',
      cfg.path,
    ]);
    expect(code, 0);
    final table = jsonDecode(out) as Map<String, dynamic>;
    expect(table['cachePrefix'], 'zz');
    expect((table['core'] as List), hasLength(1));
  });

  test('--check-only passes without manifest', () {
    final dir = fixture(baseBuild());
    expect(cli([dir.path, '--check-only']).$1, 0);
  });

  test('manifest divergence exits 1 naming the file', () {
    final dir = fixture(baseBuild());
    writeManifest(dir, [
      {
        'url': 'assets/bible/nvi.2a2a2a2a.json',
        'hash': '00000000',
        'size': 3,
        'urlHashed': true,
      },
    ]);
    for (final extra in [
      <String>[],
      ['--check-only'],
      ['--print-table'],
    ]) {
      final (code, out, err) = cli([dir.path, ...extra]);
      expect(code, 1);
      expect(err, contains('nvi.2a2a2a2a.json'));
      expect(out, isEmpty);
    }
  });

  test('usage errors exit 2', () {
    final dir = fixture(baseBuild());
    expect(cli([]).$1, 2);
    expect(cli([dir.path, 'extra']).$1, 2);
    expect(cli(['/no/such/dir']).$1, 2);
    expect(cli([dir.path, '--nope']).$1, 2);
    expect(cli([dir.path, '--config', '/no/such.yaml']).$1, 2);
    expect(cli([dir.path, '--release-id', 'bad id']).$1, 2);
  });

  test('invalid config exits 2', () {
    final dir = fixture(baseBuild());
    final cfg = File('${dir.path}/bad.yaml')..writeAsStringSync('core: 3');
    expect(cli([dir.path, '--config', cfg.path]).$1, 2);
  });

  test('real executable propagates exit codes', () {
    final dir = fixture(baseBuild());
    ProcessResult run(List<String> a) => Process.runSync(
      Platform.resolvedExecutable,
      ['run', 'pillar_web_sw:generate', ...a],
    );
    expect(run([dir.path, '--check-only']).exitCode, 0);
    expect(run([]).exitCode, 2);
    writeManifest(dir, [
      {
        'url': 'main.0a0a0a0a.js',
        'hash': '0a0a0a0a',
        'size': 1,
        'urlHashed': true,
      },
    ]);
    expect(run([dir.path]).exitCode, 1);
  });
}
