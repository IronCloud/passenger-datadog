# Passenger status XML reference

`passenger_datadog` reads `passenger-status --show=xml` and forwards the values
below to Datadog as gauges. All element lookups are defensive: absent or empty
elements are simply skipped, which is what keeps the gem working across
Passenger 4, 5, and 6 despite schema drift.

Metric keys are built as `passenger[.<supergroup>].<key>`. When more than one
supergroup is present, a normalized supergroup name is inserted into the key
(e.g. `/passenger_datadog (development)` -> `passenger_datadog_development`).

## Supergroup name normalization

Normalization replaces `-` and whitespace with `_`, then removes every remaining
non-word character **and every digit**:

| Supergroup name | Key segment |
|---|---|
| `/passenger_datadog (development)` | `passenger_datadog_development` |
| `/var/www/app (production)` | `varwwwapp_production` |
| `app1 staging` | `app_staging` |

Because digits are stripped, two supergroups whose names differ only by a digit
(`app1`, `app2`) normalize to the same key segment and their metrics land on the
same series, distinguished only by the `passenger-process:<index>` tag — which
also restarts at 0 in each supergroup. This is long-standing behavior that
dashboards are built on, so it is pinned by specs rather than changed; changing
it would rename metrics for every consumer.

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

## Degraded output

`passenger-status` does not always return a document, and none of these cases is
an error worth crashing the collector over:

| Output | Behavior |
|---|---|
| Empty | Warns `passenger-status produced no output` and skips the run. Usually a `PATH` problem under systemd rather than an idle Passenger. |
| Non-XML (e.g. a one-line `command not found`) | Warns `passenger-status produced no XML`, echoing the first line, and skips the run. |
| The instance list, printed when more than one Passenger instance is running and `passenger-status` will not guess between them | Same: warns and skips. Captured verbatim in `spec/fixtures/passenger_6_multiple_instances.txt`. The collector resumes by itself once one instance remains. |
| Truncated or malformed XML | Parses to a document with no matching elements, so nothing is sent. |
| An element present but empty or whitespace-only | Skipped; no gauge is emitted for it. |

## Fixtures

Fixtures used by the spec suite live in `spec/fixtures/`:

* `passenger_4_status.xml`
* `passenger_5_status.xml`
* `passenger_5_status_multiple_supergroups.xml`
* `passenger_6_status.xml`
* `passenger_6_status_no_processes.xml` — a group with `<processes/>` empty,
  captured from a 6.1.8 instance started with `--min-instances 0` that was never
  sent a request
* `passenger_6_multiple_instances.txt` — not XML; the instance list described
  under [Degraded output](#degraded-output)

Passenger's `disabling`/`disabled` process states have no fixture: producing them
needs a rolling restart, which is a Passenger Enterprise feature. `detach-process`
on the open-source build replaces the process without ever reporting a non-zero
count for either (verified by polling `passenger-status` at 100ms through a
detach on 6.1.8). The parsers read those counts from the same defensive lookup
as everything else, and the zero case is covered by every fixture.

These are captured verbatim from live instances; to support a new Passenger
version, capture real output rather than hand-writing XML. Specs that exercise
parsing rules rather than a version's schema (`spec/parsers/base_spec.rb`, the
prefix examples in `spec/passenger_datadog_spec.rb`) use inline XML instead, so
the fixtures stay honest records of what Passenger actually emits.
