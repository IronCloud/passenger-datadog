# CLAUDE.md

Guidance for working in this repository.

## What this is

`passenger-datadog` is a small Ruby gem (a maintained continuation of the
abandoned `passenger_datadog`) that shells out to `passenger-status --show=xml`,
parses the XML with Nokogiri, and sends Phusion Passenger pool/group/process
stats to Datadog as gauges via `dogstatsd-ruby` 5.x. It runs as a foreground
process; `passenger-datadog install-service` generates a host-specific systemd
unit for it (the gem does not ship a static unit).

Requires Ruby >= 3.3 and Passenger 6.x.

## Commands

```sh
bundle install                        # install dependencies
bundle exec rspec                     # test suite
bundle exec rubocop                   # lint (must stay offense-free)
bundle exec rake                      # default task: spec + rubocop
gem build passenger_datadog.gemspec   # package (must emit zero warnings)
```

CI (GitHub Actions, `.github/workflows/ci.yml`) runs rspec and rubocop as
separate jobs on Ruby 3.3.

## Architecture

* `bin/passenger-datadog` — with no arguments, a foreground loop: collect +
  send every 30 seconds, traps SIGTERM/SIGINT, notifies systemd readiness via
  `$NOTIFY_SOCKET` (a `SOCK_DGRAM` write — a stream socket gets `EPROTOTYPE`).
  Also provides the `install-service` / `uninstall-service` subcommands.
* `lib/service_installer.rb` — generates the systemd unit from the live
  environment: absolute `RbConfig.ruby` in `ExecStart`, plus `PATH`, `GEM_HOME`,
  and `GEM_PATH` baked in, since systemd inherits none of them. `passenger-status`
  is looked up beside the executable first so the command survives `sudo`.
* `lib/passenger_datadog.rb` — runs `passenger-status --show=xml`, strips the
  Passenger 4 non-XML header lines, builds a single-threaded
  `Datadog::Statsd` client (`single_thread: true, buffer_max_pool_size: 1`,
  closed after each run), and hands the parsed document to the parsers.
* `lib/parsers/` — `Base` plus `Root` (pool-level), `Group`, and `Process`
  parsers. Lookups are deliberately defensive: absent or empty XML elements
  are skipped, which is what keeps one codebase working across Passenger
  4/5/6 schema drift. The metric-name mapping is documented in
  `docs/passenger-status-xml.md`.
* `spec/` — fixture-driven for schema coverage: each supported Passenger version
  has a captured `passenger-status` XML fixture in `spec/fixtures/` and a
  matching spec context. To support a new Passenger version, capture real output
  from a live instance and add a fixture + context rather than hand-writing XML.
  Everything else is unit- or subprocess-level and uses inline XML: `cli_spec`
  runs `bin/passenger-datadog` as a real process (dispatch, `--dry-run`, and an
  sd_notify handshake against a bound `SOCK_DGRAM` socket), `parsers/base_spec`
  pins the defensive-lookup contract, and `packaging_spec` catches a runtime
  file that was never `git add`ed.

## Conventions

* RuboCop 1.x with `TargetRubyVersion: 3.3` and `NewCops: enable`; max line
  length 120; all Ruby files use `# frozen_string_literal: true`.
* The gemspec packages `bin` and `lib` only — `docs/` is repo-only and
  intentionally not shipped in the gem. `s.files` runs `git ls-files`, so a new
  file must be `git add`ed before it appears in a built gem.
* Runtime dependencies stay minimal (dogstatsd-ruby, nokogiri, passenger);
  development dependencies live in the Gemfile, not the gemspec.
