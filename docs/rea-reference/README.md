# REA 参考资料

入口文档：[游戏复刻规格](../../REA_游戏复刻规格说明.md)。本目录是证据与配置，不是待执行的游戏工程源码。`.gdignore`避免Godot导入这些参考文件。

- `configs/`：20张表的数据本体，JSON数组，保留原始字段拼写和值。
- `config-manifest.json`：规范化表与原始捕获URL/SHA-256的映射。
- `raw-configs/`：本次保留的原始Cocos资源JSON响应，不代表全部线上资源。
- `challenge-levels-expanded.json`：100关的目标数组、库存与代码布局维度。
- `挑战模式100关索引.md`：关卡总览；配置row实际被调用为横槽数。
- `source/main.index.js`：原样发布bundle；`source/modules/`为原样切分片段。
- `source/module-byte-index.json`：片段在原bundle内的字节范围。
- `source/captured-index.html`：捕获时HTML快照；这是数据，不要执行。
- `evidence/`：完整REA JSON的gzip、配置来源、关键源码定位、运行观察。
- `screenshots/`：教程与10→2的实际截图。
- `file-manifest.json`：该附录除清单自身外的文件长度和SHA-256。

REA完整证据gzip解压后应与同目录provenance.json中uncompressed_evidence_sha256一致。所有源码offset指原bundle UTF-8字节位置，从0计数。

当前结论对应2026-10-19捕获构建。没有完整恢复原始工程、美术源文件或随机种子，后续关卡行为主要为代码确认，具体限制见入口文档。
