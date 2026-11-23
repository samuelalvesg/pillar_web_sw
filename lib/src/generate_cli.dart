/// Arquivo: generate_cli.dart
/// Módulo: pillar_web_sw / CLI
/// Descrição: Implements `dart run pillar_web_sw:generate`: scan, cross-check,
///   classify, and print the summary or the JSON table.
/// Dependências: package:args, build_scanner, manifest_check, classifier.
/// Premissas: exit codes are 0 ok, 1 manifest divergence, 2 usage error.
///   Writing the worker files is a later step; this only prints.
/// Edge Cases: without --config, ./web_sw.yaml is used when present,
///   otherwise defaults; an explicit missing --config is a usage error.
library;

import 'dart:io';

import 'package:args/args.dart';

import 'build_scanner.dart';
import 'classifier.dart';
import 'manifest_check.dart';
import 'web_sw_config.dart';

const exitOk = 0;
const exitDivergence = 1;
const exitUsage = 2;

final _releaseIdPattern = RegExp(r'^[A-Za-z0-9._-]+$');

ArgParser _parser() => ArgParser()
  ..addOption('config', help: 'Caminho do web_sw.yaml (padrão: ./web_sw.yaml).')
  ..addOption('release-id', help: 'Usa este id em vez do calculado.')
  ..addFlag('check-only', negatable: false, help: 'Só confere o manifesto.')
  ..addFlag('print-table', negatable: false, help: 'Imprime a tabela em JSON.');

String usage() =>
    'Uso: dart run pillar_web_sw:generate <build/web> [opções]\n'
    '${_parser().usage}';

/// Runs the command; never throws for bad input.
int runGenerate(
  List<String> args, {
  required StringSink out,
  required StringSink err,
}) {
  final ArgResults parsed;
  try {
    parsed = _parser().parse(args);
  } on FormatException catch (e) {
    err.writeln('${e.message}\n${usage()}');
    return exitUsage;
  }
  if (parsed.rest.length != 1) {
    err.writeln('Informe exatamente um diretório de build.\n${usage()}');
    return exitUsage;
  }
  final buildDir = Directory(parsed.rest.single);
  if (!buildDir.existsSync()) {
    err.writeln('Diretório não encontrado: ${buildDir.path}');
    return exitUsage;
  }
  final releaseOverride = parsed['release-id'] as String?;
  if (releaseOverride != null && !_releaseIdPattern.hasMatch(releaseOverride)) {
    err.writeln('--release-id deve usar só letras, números, ".", "_" ou "-".');
    return exitUsage;
  }

  final WebSwConfig config;
  try {
    config = _loadConfig(parsed['config'] as String?);
  } on ConfigException catch (e) {
    err.writeln(e.message);
    return exitUsage;
  }

  final entries = scanBuild(buildDir);
  final problems = checkAgainstManifest(buildDir, entries);
  if (problems.isNotEmpty) {
    err.writeln('Manifesto diverge do disco:');
    problems.forEach((p) => err.writeln('  $p'));
    return exitDivergence;
  }

  final classification = classify(entries, config);
  final releaseId = releaseOverride ?? computeReleaseId(classification.core);
  if (parsed['check-only'] as bool) {
    out.writeln('Manifesto conferido: ${entries.length} arquivos.');
    return exitOk;
  }
  if (parsed['print-table'] as bool) {
    final table = buildTable(
      classification: classification,
      config: config,
      releaseId: releaseId,
    );
    out.writeln(encodeTable(table));
    return exitOk;
  }
  out.writeln(
    'release_id $releaseId: ${classification.core.length} no núcleo, '
    '${classification.onDemand.length} sob demanda, '
    '${classification.ignored.length} ignorados.',
  );
  return exitOk;
}

WebSwConfig _loadConfig(String? path) {
  final file = File(path ?? 'web_sw.yaml');
  if (!file.existsSync()) {
    if (path != null) throw ConfigException('Config não encontrada: $path');
    return const WebSwConfig();
  }
  return WebSwConfig.parse(file.readAsStringSync());
}
