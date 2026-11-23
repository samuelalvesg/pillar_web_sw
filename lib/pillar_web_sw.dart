/// Arquivo: pillar_web_sw.dart
/// Módulo: pillar_web_sw
/// Descrição: Public API of the generator (scan, check, classify, table).
/// Dependências: ver arquivos em src/.
/// Premissas: pure Dart, no Flutter dependency.
/// Edge Cases: none.
library;

export 'src/build_scanner.dart' show isExcluded, isUrlHashed, scanBuild;
export 'src/classifier.dart'
    show Classification, buildTable, classify, computeReleaseId, encodeTable;
export 'src/generate_cli.dart' show runGenerate;
export 'src/manifest_check.dart' show checkAgainstManifest;
export 'src/manifest_entry.dart' show ManifestEntry;
export 'src/web_sw_config.dart' show ConfigException, WebSwConfig;
export 'src/worker_writer.dart'
    show renderKillSwitch, renderWorker, writeKillSwitch, writeWorkerFiles;
