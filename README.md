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
The gem ships a systemd unit at `packaging/passenger-datadog.service`:

```
$ sudo install -m 644 packaging/passenger-datadog.service /etc/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemctl enable --now passenger-datadog
```
