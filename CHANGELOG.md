# Change log

## 2.0.0 (2026-08-14)

### Changes

* Require Ruby >= 3.3 and Passenger >= 6.0
* Upgrade `dogstatsd-ruby` to 5.x; the client is configured for single-threaded
  operation so metrics are flushed per run without leaking sender threads
* Replace the `daemons`-based daemonization with a foreground process supervised
  by systemd (`packaging/passenger-datadog.service`)
* Replace Travis CI with GitHub Actions
* Upgrade RuboCop to 1.x and refresh the configuration
* Move development dependencies from the gemspec into the Gemfile
* Add a Passenger 6.1 fixture captured from a live instance and a matching spec


## 1.1.0 (2018-04-27)

### New features

* Improve support for multiple supergroups. Metrics for multiple supergroups will now be prefixed with name of the supergroup. ([@krasnoukhov][])
* Record the group metrics `get_wait_list_size` and `disable_wait_list_size`. ([@krasnoukhov][])


## 1.0.0 (2018-01-17)

### Changes

* Drop support for Ruby < 2.2
* Update gem dependencies

### Bug Fixes

* Do not send empty stats from Passenger 4 to Datadog


## 0.2.1 (2015-10-23)

### Changes

* Add and enforce the use of `UTF-8` encoding. ([@rrosenblum][])
* Ownership of repo has transferred from `rrosenblum` to `manheim`. ([@rrosenblum][])


## 0.2.0 (2015-10-22)

### Changes

* Change `passenger-datadog` to do what `passenger-datatdog-daemon` did before


## 0.1.0 (2015-10-22)

* Initial release

[@rrosenblum]: https://github.com/rrosenblum
[@krasnoukhov]: https://github.com/krasnoukhov
