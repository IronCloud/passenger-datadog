[![Gem Version](https://badge.fury.io/rb/passenger-datadog.svg)](https://badge.fury.io/rb/passenger-datadog)
[![CI](https://github.com/IronCloud/passenger-datadog/actions/workflows/ci.yml/badge.svg)](https://github.com/IronCloud/passenger-datadog/actions/workflows/ci.yml)
[![License](http://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

# passenger-datadog

A continuation of the abandoned [passenger_datadog](https://rubygems.org/gems/passenger_datadog)
gem by [Ryan Rosenblum](https://github.com/rrosenblum), maintained by IronCloud.

Inspired by [passengeri-datadog-monitor](https://github.com/Sjeanpierre/passenger-datadog-monitor)

This gem can be used to send stats from Passenger to Datadog. It makes use of
the command `passenger-status`, and the Ruby implementation of `statsd`
provided by [dogstatsd-ruby](https://github.com/DataDog/dogstatsd-ruby).

In order to gather stats on all Passenger instances, Passenger recommends
running `passenger-status` as `root`. Therefore, it is recommended that
`passenger-datadog` be run as `root` as well.

If running `passenger-datadog` as a user other than the user that owns the application
in Passenger, make sure that same version of Passenger is installed for both users.

## Installation
```
$ gem install passenger-datadog
```

## Support
* Ruby >= 3.3
* Passenger >= 6.0

## Usage

### Foreground process
```
$ passenger-datadog
```

The process collects Passenger stats and sends them to Datadog every 30
seconds. It runs in the foreground and shuts down cleanly on `SIGTERM`/`SIGINT`.

### As a systemd service
Generate and install a unit for this host, then start it:

```
$ sudo passenger-datadog install-service
$ sudo systemctl enable --now passenger-datadog
```

`install-service` resolves the Ruby interpreter, the executable, and
`passenger-status` on the machine it runs on, and writes those absolute paths
into `/etc/systemd/system/passenger-datadog.service`. Use `--dry-run` to print
the unit without writing it, and `uninstall-service` to remove it.

Under rvm/rbenv/asdf, `sudo` drops the gem environment, so pass it through:

```
$ sudo env PATH="$PATH" GEM_HOME="$GEM_HOME" GEM_PATH="$GEM_PATH" \
    passenger-datadog install-service
```

Regenerate the unit with `--force` after a Ruby upgrade. See
[docs/systemd.md](docs/systemd.md) for the full guide.

## Release

Releases use RubyGems [trusted publishing](https://guides.rubygems.org/trusted-publishing) —
no API tokens. The trusted publisher must be registered for this repo and the
`release.yml` workflow on RubyGems.org (a pending publisher becomes a normal
one after its first push). To release:

1. Bump the version in `passenger_datadog.gemspec` and add a `CHANGELOG.md` entry.
2. Commit, tag, and push:

```
$ git tag v2.0.0
$ git push origin v2.0.0
```

`.github/workflows/release.yml` builds the gem and pushes it to RubyGems.org,
authenticating with an OIDC token scoped to this gem.
