# Changelog

## Não lançado

- Gerador `dart run pillar_web_sw:generate`: varredura de `build/web`, tabela no formato do `precache_manifest.json`, conferência com o manifesto do SDK, `release_id` por conteúdo, `web_sw.yaml` e classificação núcleo / sob demanda / ignorados (`--print-table`, `--check-only`, `--release-id`).
- Gravação de `app-service-worker.js` (modelo do worker com a tabela embutida, determinístico) e `app-sw-register.js` no diretório de build; `--check-only` e `--print-table` continuam sem gravar.
- `--kill-switch`: worker que apaga os caches `<cachePrefix>-*` e se desregistra, no mesmo nome do worker.
- Testes: texto gerado em Dart e cenários do worker em Node (mocks de `caches`/`fetch`/`self`), pulados quando o Node não existe.
