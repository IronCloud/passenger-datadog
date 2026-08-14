# Passenger status XML reference

`passenger_datadog` reads `passenger-status --show=xml` and forwards the values
below to Datadog as gauges. All element lookups are defensive: absent or empty
elements are simply skipped, which is what keeps the gem working across
Passenger 4, 5, and 6 despite schema drift.

Metric keys are built as `passenger[.<supergroup>].<key>`. When more than one
supergroup is present, a normalized supergroup name is inserted into the key
(e.g. `/passenger_datadog (development)` -> `passenger_datadog_development`).

## Info (pool-level)

`passenger-status --show=xml` root element: `<info>`.

| XML element | Datadog metric |
|-------------|----------------|
| `process_count` | `passenger.pool.used` |
| `max` | `passenger.pool.max` |
| `get_wait_list_size` | `passenger.request_queue` |

## Group

Each `<supergroup>` contains one or more `<group>` elements.

| XML element | Datadog metric |
|-------------|----------------|
| `capacity_used` | `passenger.<supergroup>.capacity_used` |
| `get_wait_list_size` | `passenger.<supergroup>.get_wait_list_size` |
| `disable_wait_list_size` | `passenger.<supergroup>.disable_wait_list_size` |
| `processes_being_spawned` | `passenger.<supergroup>.processes_being_spawned` |
| `enabled_process_count` | `passenger.<supergroup>.enabled_process_count` |
| `disabling_process_count` | `passenger.<supergroup>.disabling_process_count` |
| `disabled_process_count` | `passenger.<supergroup>.disabled_process_count` |

## Process

Each `<process>` is reported with tag `passenger-process:<index>` where
`<index>` is its position within its group (0-based).

| XML element | Datadog metric |
|-------------|----------------|
| `processed` | `passenger.<supergroup>.processed` |
| `sessions` | `passenger.<supergroup>.sessions` |
| `busyness` | `passenger.<supergroup>.busyness` |
| `concurrency` | `passenger.<supergroup>.concurrency` |
| `cpu` | `passenger.<supergroup>.cpu` |
| `rss` | `passenger.<supergroup>.rss` |
| `private_dirty` | `passenger.<supergroup>.private_dirty` |
| `pss` | `passenger.<supergroup>.pss` |
| `swap` | `passenger.<supergroup>.swap` |
| `real_memory` | `passenger.<supergroup>.real_memory` |
| `vmsize` | `passenger.<supergroup>.vmsize` |

## Version differences

| Version | Notes |
|---------|-------|
| Passenger 4 | Output is prefixed with 3 non-XML header lines (`Version :`, `Date :`, `Instance:`) before the `<?xml ...?>` declaration. The gem strips them (`lib/passenger_datadog.rb`). Processes use `<utilization>`; there is no `<busyness>`. |
| Passenger 5 | XML starts with the declaration. `<busyness>` appears on processes; multiple supergroups may exist. |
| Passenger 6 | Same `--show=xml` interface. Schema details verified against a live 6.1 capture in `spec/fixtures/passenger_6_status.xml`. |

Fixtures used by the spec suite live in `spec/fixtures/`:

* `passenger_4_status.xml`
* `passenger_5_status.xml`
* `passenger_5_status_multiple_supergroups.xml`
* `passenger_6_status.xml`
