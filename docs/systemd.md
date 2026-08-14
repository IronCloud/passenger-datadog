# Running as a systemd service

Since version 2.0.0 the daemon runs as a foreground process supervised by
systemd. There is no built-in daemonization; the service manager handles
process lifecycle, restarts, and log capture.

The gem does not ship a unit file. It generates one for the host it is running
on, because the paths that matter — the Ruby interpreter, the executable, and
`passenger-status` — differ on every installation and are not knowable at
packaging time.

## Installing

```sh
sudo passenger-datadog install-service
sudo systemctl enable --now passenger-datadog
```

This writes `/etc/systemd/system/passenger-datadog.service` and runs
`systemctl daemon-reload`. It deliberately does not start the service; pass
`--enable-now` to do that in the same step.

### Under rvm, rbenv, or asdf

`sudo` resets `PATH` to `secure_path` and drops `GEM_HOME`/`GEM_PATH`, so the
command above will not find the executable. Pass the environment through:

```sh
sudo env PATH="$PATH" GEM_HOME="$GEM_HOME" GEM_PATH="$GEM_PATH" \
  passenger-datadog install-service
```

The generated unit records these values, so the *service* does not need them at
runtime — only the install step does.

### Options

| Option | Effect |
|---|---|
| `--dry-run` | Print the generated unit instead of writing it. |
| `--force` | Overwrite an existing unit file. |
| `--enable-now` | Run `systemctl enable --now` after installing. |
| `--user`, `--group` | `User=`/`Group=` for the unit (default `root`). |
| `--passenger-status PATH` | Override the auto-detected `passenger-status`. |

Review before writing anything:

```sh
passenger-datadog install-service --dry-run
```

## What gets generated

```ini
[Service]
Type=notify
NotifyAccess=main
ExecStart=/usr/share/rvm/rubies/ruby-3.3.1/bin/ruby /usr/share/rvm/gems/ruby-3.3.1/bin/passenger-datadog
Environment=PATH=/usr/share/rvm/gems/ruby-3.3.1/bin:/usr/share/rvm/rubies/ruby-3.3.1/bin:/usr/local/sbin:...
Environment=GEM_HOME=/usr/share/rvm/gems/ruby-3.3.1
Environment=GEM_PATH=/usr/share/rvm/gems/ruby-3.3.1:...
EnvironmentFile=-/etc/default/passenger-datadog
Restart=on-failure
RestartSec=5s
User=root
Group=root
```

Why each piece is there:

* **`ExecStart` names the interpreter explicitly.** The executable is passed as
  an argument to an absolute Ruby path, so neither the shebang line nor
  systemd's `PATH` has to resolve anything. A bare
  `ExecStart=/usr/local/bin/passenger-datadog` fails with `203/EXEC` on any
  Ruby that is not the system one.
* **`Environment=PATH`** includes the directory holding `passenger-status`.
  The collector shells out to it by name, and systemd's default `PATH` does not
  include gem bin directories.
* **`Environment=GEM_HOME`/`GEM_PATH`** pin the gem environment. Version
  managers set these from shell integration that systemd never runs.
* **`User=root`** because Passenger recommends running `passenger-status` as
  root so it can see every Passenger instance on the host.

The unit is specific to the Ruby it was generated for. **After a Ruby upgrade,
regenerate it:**

```sh
sudo passenger-datadog install-service --force
sudo systemctl restart passenger-datadog
```

## Collector configuration

The collector runs every 30 seconds. The Datadog client honors the usual
environment variables for the DogStatsD endpoint. Put them in
`/etc/default/passenger-datadog`, which the unit reads if it exists:

```sh
DD_AGENT_HOST=10.0.0.5
DD_DOGSTATSD_PORT=8125
DD_TAGS=env:production,role:web
```

`DD_DOGSTATSD_SOCKET`, `DD_ENV`, `DD_SERVICE`, `DD_VERSION`, `DD_CARDINALITY`
and the rest are supported per the dogstatsd-ruby docs. Restart the service
after changing the file.

## Operating

```sh
systemctl status passenger-datadog   # current state
systemctl restart passenger-datadog  # restart
journalctl -u passenger-datadog -f   # follow logs (stdout/stderr)
```

Stopping sends `SIGTERM`; the process shuts down cleanly after the current
collection run.

```sh
systemctl stop passenger-datadog
```

## Removing

```sh
sudo passenger-datadog uninstall-service
```

Disables the service, removes the unit, and reloads systemd. Safe to run when
nothing is installed.

## Troubleshooting

**`status=203/EXEC`** — `ExecStart` points at something that does not exist,
usually because the unit was hand-written or the Ruby was upgraded after the
unit was generated. Regenerate with `--force`.

**Service is `active (running)` but no metrics arrive** — check the journal for
`passenger-status produced no output`. That means the collector ran but got
nothing back: either Passenger genuinely is not running, or `passenger-status`
is not on the unit's `PATH`. Compare:

```sh
systemctl show passenger-datadog -p Environment
sudo passenger-status --show=xml | head -3
```

**Start times out with `Result: timeout`** — the readiness notification never
arrived. `Type=notify` requires the sd_notify write to succeed; if your platform
does not support it, change to `Type=simple` via
`systemctl edit passenger-datadog`.

**`passenger-status not found`** during install — the `passenger` gem is not
installed for the Ruby you are invoking, or `sudo` stripped the environment
(see above). Pass `--passenger-status /full/path` to override detection.
