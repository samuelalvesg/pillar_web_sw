/// Arquivo: generate.dart
/// Módulo: pillar_web_sw / executável
/// Descrição: Entry point of `dart run pillar_web_sw:generate`.
/// Dependências: package:pillar_web_sw.
/// Premissas: all logic lives in lib/ so it is testable.
/// Edge Cases: none.
library;

import 'dart:io';

import 'package:pillar_web_sw/pillar_web_sw.dart';

void main(List<String> args) {
  exitCode = runGenerate(args, out: stdout, err: stderr);
}
