# CDC connector configuration

`aether-postgres-cdc.json` is the versioned Debezium configuration registered by
`scripts/register-ecommerce-cdc.sh`. It is applied with `PUT` to
`/connectors/aether-postgres-cdc/config`, so editing this file and re-running the
script is idempotent.

Two properties exist because of the consumer on the other end, not because of
PostgreSQL. They are easy to remove by accident and expensive to debug, so the
constraints are written down here.

## `decimal.handling.mode: string`

The default, `precise`, encodes `NUMERIC` columns as Kafka Connect `bytes` with
the `org.apache.kafka.connect.data.Decimal` logical type. Through the JSON
converter with schemas enabled that reaches the topic as base64:

```json
"total_amount": "Mr4="
```

Flink's `debezium-json` format cannot turn that back into a `DECIMAL`. The field
converts to null, which surfaces much later and much further away from the cause
as

```text
Failed to deserialize consumer record ...
Caused by: java.lang.NullPointerException:
  Cannot invoke "Object.toString()" because the return value of
  "org.apache.flink.table.data.GenericRowData.getField(int)" is null
```

The task fails, the job restarts, and because the source reads from
`earliest-offset` it re-reads the same record: a poison message that loops
forever. This is a known gap in the format, tracked as
[FLINK-18758](https://issues.apache.org/jira/browse/FLINK-18758), and the
workaround belongs on the producer side.

`string` emits the same value as a JSON string (`"129.90"`), which Flink parses
into `DECIMAL(12, 2)` without loss. `double` would also work but trades away
exactness for no benefit here.

## Timestamps: the consumer needs ISO-8601 and `TIMESTAMP_LTZ`

`TIMESTAMPTZ` columns arrive as `io.debezium.time.ZonedTimestamp`, an RFC 3339
string such as `2026-10-26T19:27:53.701115Z`. Two consumer-side settings have to
match it, and each fails differently when it does not:

- `debezium-json.timestamp-format.standard` defaults to `SQL`, whose formatter
  separates date and time with a space. Parsing fails at the `T`, reported as
  `could not be parsed at index 10` — an index, not a reason.

- With `ISO-8601`, a plain `TIMESTAMP` column uses `ISO_LOCAL_DATE_TIME`, which
  accepts the `T` but not the trailing `Z`. Only `TIMESTAMP_LTZ` uses the
  formatter that appends `'Z'`.

Precision is milliseconds, while Debezium emits microseconds, so the last three
digits are dropped. That is deliberate for now; `TIMESTAMP_LTZ(6)` plus
`time.precision.mode=adaptive_time_microseconds` would preserve them.

Changing any of this changes what the reader must expect, so the connector
configuration and `services/streaming/sql/pipeline.sql.in` have to move together.

## `tombstones.on.delete: false`

A delete produces both a `-D` change event and a null-valued tombstone. Flink's
`debezium-json` does not expect the tombstone and fails on it. The changelog is
complete without it.

## Changing the encoding is not retroactive

Records already in the topic keep the encoding they were written with. After
changing either property, the topics have to be recreated for the pipeline to see
a consistent stream:

```bash
make reset          # destroys postgres, kafka and seaweedfs volumes
make up
make verify-cdc     # registers the connector, which re-snapshots
make pipeline
```

Resetting also drops the Iceberg warehouse, so it re-snapshots from an empty
table set rather than mixing encodings across snapshots.
