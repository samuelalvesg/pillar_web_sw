# Changelog

## Não lançado

- `canvaskit/**` passa a entrar na tabela quando existe no disco (build com `--no-web-resources-cdn`), sem hash no nome (`urlHashed: false`); a classificação por `web_sw.yaml` decide núcleo, sob demanda ou ignorado. `*.symbols` e `*.map` continuam fora.
- Gerador `dart run pillar_web_sw:generate`: varredura de `build/web`, tabela no formato do `precache_manifest.json`, conferência com o manifesto do SDK, `release_id` por conteúdo, `web_sw.yaml` e classificação núcleo / sob demanda / ignorados (`--print-table`, `--check-only`, `--release-id`).
- Gravação de `app-service-worker.js` (modelo do worker com a tabela embutida, determinístico) e `app-sw-register.js` no diretório de build; `--check-only` e `--print-table` continuam sem gravar.
- `--kill-switch`: worker que apaga os caches `<cachePrefix>-*` e se desregistra, no mesmo nome do worker.
- Testes: texto gerado em Dart e cenários do worker em Node (mocks de `caches`/`fetch`/`self`), pulados quando o Node não existe.
- Worker: a instalação busca `config.js` (`cache: 'reload'`) e o guarda em `<prefix>-runtime`, em melhor esforço (falha não rejeita a instalação; vai para `configPrefetchError` no status), para a reabertura offline ter a configuração do tenant.
- Worker: `clients.claim()` passa a depender de uma marca de primeira instalação gravada no `install` (`registration.active` nulo), não mais da ausência de outro cache de release.
- Correção: o `release_id` passa a incluir a versão do modelo do worker, e a instalação do worker baixa para `<prefix>-core-<id>-installing` e promove só no sucesso. Antes, um worker novo com o mesmo núcleo apagava o cache que o worker ativo servia e, se a instalação falhasse, o app deixava de abrir offline. Os `release_id` gerados mudam uma vez com esta versão.
- Correção: a instalação do worker não confere mais o hash de HTML e texto (`.html`, `.htm`, `.svg`, `.xml`, `.txt`, `.css`, `.json`), só o status 200, porque proxies como o Cloudflare reescrevem esses arquivos na borda e a instalação falhava sempre. Cada entrada do núcleo na tabela ganha `check` (`hash` ou `status`); nova chave opcional `noHashCheck` no `web_sw.yaml`. Código e binários continuam com hash. O `release_id` não mudou de regra.
