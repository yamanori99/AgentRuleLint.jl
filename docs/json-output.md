# CLI output formats

`--format=json` writes JSONL: one object per line, in this order: `header`,
zero or more `diagnostic` records, then `summary`.

Consumers must ignore unknown keys.

Field shapes: [`schemas/check-jsonl.schema.json`](../schemas/check-jsonl.schema.json).
