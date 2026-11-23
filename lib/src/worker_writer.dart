/// Arquivo: worker_writer.dart
/// Módulo: pillar_web_sw / gravação
/// Descrição: Renders the worker, the kill switch and the registration
///   script from their templates and writes them into the build directory.
/// Dependências: dart:convert, dart:io, templates/.
/// Premissas: output is a pure function of the table (or prefix), so equal
///   input gives byte-identical files.
/// Edge Cases: the table is substituted by position, never by a global
///   replace, so `$` or the token inside a url cannot corrupt the script.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'templates/app_service_worker_template.dart';
import 'templates/kill_switch_template.dart';
import 'templates/register_template.dart';

/// Version of the worker template: 8 hex of the SHA-256 of its text, so any
/// edit to the template changes it without a constant to remember.
final String workerModelId = sha256
    .convert(utf8.encode(appServiceWorkerTemplate))
    .toString()
    .substring(0, 8);

const workerFileName = 'app-service-worker.js';
const registerFileName = 'app-sw-register.js';

String _fill(String template, String token, String value) {
  final at = template.indexOf(token);
  return template.replaceRange(at, at + token.length, value);
}

/// The worker with [table] embedded as JSON.
String renderWorker(Map<String, Object> table) => _fill(
  appServiceWorkerTemplate,
  tableToken,
  const JsonEncoder.withIndent('  ').convert(table),
);

/// The emergency worker that wipes `<cachePrefix>-*` caches.
String renderKillSwitch(String cachePrefix) =>
    _fill(killSwitchTemplate, prefixToken, jsonEncode(cachePrefix));

/// Writes the worker and the registration script into [buildDir].
void writeWorkerFiles(Directory buildDir, Map<String, Object> table) {
  File(
    '${buildDir.path}/$workerFileName',
  ).writeAsStringSync(renderWorker(table));
  File('${buildDir.path}/$registerFileName').writeAsStringSync(registerScript);
}

/// Writes only the kill switch, under the worker's own file name.
void writeKillSwitch(Directory buildDir, String cachePrefix) {
  File(
    '${buildDir.path}/$workerFileName',
  ).writeAsStringSync(renderKillSwitch(cachePrefix));
}
