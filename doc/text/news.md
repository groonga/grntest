# News

## 1.7.5: 2024-04-12

### Improvements

  * `#@generate-series`: Improved performance.

  * `#@require-env`: Added to run tests only when the given
    environment variable is defined.

## 1.7.4: 2024-04-05

### Improvements

  * http: Added support for canceled requests.

## 1.7.3: 2024-02-20

### Improvements

  * reporter: benchmark-json: Added support for omission.

## 1.7.2: 2024-02-06

### Improvements

  * arrow: Added support for empty result.

  * reporter: benchmark-json: Added support for reporting memory leak
    information.

  * reporter: benchmark-json: Added interface and in/out types to
    benchmark name.

## 1.7.1: 2024-02-05

### Improvements

  * benchmark: Removed load preparation part from elapsed time.

## 1.7.0: 2024-02-05

### Fixes

  * reporter: benchmark-json: Fixed a bug that invalid JSON may be
    generated.

## 1.6.9: 2024-02-05

### Improvements

  * reporter: benchmark-json: Added a test suite name to benchmark name.

## 1.6.8: 2024-02-05

### Fixes

  * reporter: benchmark-json: Fixed a bug that invalid JSON is
    generated.

## 1.6.7: 2024-02-05

### Improvements

  * Added benchmark mode. It uses Google Benchmark compatible JSON
    output.

## 1.6.6: 2023-10-24

### Improvements

  * arrow: Removed a needless new line.

## 1.6.5: 2023-10-24

### Improvements

  * Added support for trace log.

## 1.6.4: 2023-10-21

### Improvements

  * arrow: Added support for metadata normalization.

## 1.6.3: 2023-09-18

### Improvements

  * reporter: stream: Changed to show worker ID for each test.

  * Added support for backtrace pattern provided by mruby 3.2.0.

### Fixes

  * reporter: stream: Fixed a bug that worker ID isn't outputted.

## 1.6.2: 2023-08-24

### Improvements

  * reporter: stream: Changed to show "start" message in multi-workers
    mode.

## 1.6.1: 2023-08-11

### Improvements

  * `--n-workers`: Use the max number of cores by default.

## 1.6.0: 2023-07-21

### Improvements

  * groonga-nginx: Set `client_body_temp_path`.

## 1.5.9: 2023-07-21

### Improvements

  * groonga-nginx: Created `logs/` directory.

## 1.5.8: 2023-07-21

### Improvements

  * `--random-seed`: Added.

  * xml: Accepted negative elapsed time.

  * Added support for groonga-nginx.

## 1.5.7: 2023-03-08

### Improvements

  * Added support for `rr`.

  * Improved backtrace normalization on macOS.

  * Added `add-substitution` and `remove-substitution` to unify common
    tests for `NormalizerNFKC*`.

## 1.5.6: 2022-03-16

### Improvements

  * Added `groonga-synomym` to required dependencies.

## 1.5.5: 2022-01-18

### Improvements

  * Added support for normalizing function name.

## 1.5.4: 2022-01-17

### Improvements

  * `http`: Added support for long query.

## 1.5.3: 2021-08-14

### Improvements

  * `generate-series`: Added support for multi-byte characters.

## 1.5.2: 2021-08-05

### Improvements

  * `stdio`: Improved may be slow command processing.

  * `copy-path`: Handled error.

  * `generate-series`: Improved multi threading support.

## 1.5.1: 2021-07-16

### Improvements

  * `http`: Improved response check.

## 1.5.0: 2021-07-16

### Improvements

  * `http`: Added response code check.

  * `groonga-httpd`: Increased the max body size.

## 1.4.9: 2021-07-12

### Improvements

  * Added `synonyms-generate` directive.

## 1.4.8: 2020-12-09

### Fixes

  * `require-apache-arrow`: Fixed inverted Apache Arrow version check condition.

## 1.4.7: 2020-12-08

### Improvements

  * `require-apache-arrow`: Added support for version check of Apache
    Arrow in Groonga.

## 1.4.6: 2020-12-08

### Improvements

  * Added `require-feature` directive.

## 1.4.5: 2020-11-11

### Improvements

  * Added `sleep-after-command` directive.

## 1.4.4: 2020-07-18

### Improvements

  * Added support for detecting backtrace log for MinGW build.

## 1.4.3: 2020-05-31

### Improvements

  * Removed log normalization.

## 1.4.2: 2020-05-30

### Improvements

  * Removed log level normalization.

  * Added `require-platform` directive.

  * Added support for normalizing IO open/close log message with
    additional message.

## 1.4.1: 2020-05-30

### Improvements

  * Added support for normalizing IO open/close log message.

## 1.4.0: 2020-05-16

### Improvements

  * Added support for normalizing mruby's syntax error message.

## 1.3.9: 2020-05-09

### Improvements

  * Added `progress` reporter.

  * Suppressed Apache Arrow related reports from Valgrind.

  * Improved backtrace detection.

## 1.3.8: 2020-04-23

### Improvements

  * Improved static port detection.

  * Improved backtrace detection.

## 1.3.7: 2020-03-26

### Improvements

  * Added `add-ignore-log-pattern` directive.

  * Added `remove-ignore-log-pattern` directive.

## 1.3.6: 2020-03-26

### Improvements

  * standard-io: Added support for stream output

  * Added `require-testee` directive.

  * Added `require-interface` directive.

  * Added support for Apache Arrow.

  * Added `require-apache-arrow` directive.

  * http: Added support for debug log by `GRNTEST_HTTP_DEBUG`
    environment variable.

  * Added `--use-http-chunked` option.

  * Stopped counting test failures on retry.

## 1.3.5: 2020-03-02

### Improvements

  * Added support for Ruby 2.3 again.

  * Changed to use `URI#open` to suppress a warning.

  * Added support for Apache Arrow as load data format.

  * Added `require-input-type` directive.

  * Added `--use-http-post` option.

## 1.3.4: 2019-10-11

### Improvements

  * Added support for testing with installed Groonga.

  * Added support for `send` operation in query log.

## 1.3.3: 2019-05-12

### Improvements

  * Added `eval` directive.

  * Added `plugins_directory` expandable variable.

  * Added `libtool_directory` expandable variable.

  * Added `plugin_extension` expandable variable.

## 1.3.2: 2019-05-09

### Improvements

  * Changed to use groonga-log and groonga-query-log gems.

## 1.3.1: 2018-11-19

### Improvements

  * Improved HTTP related error handling.

  * Added `--shutdown-wait-time` option.

  * Improved shutdown process for Groonga HTTP server.

## 1.3.0: 2018-11-16

### Improvements

  * Improved to force logging backtrace on crash.

  * Added `--n-retries` option.

### Fixes

  * Fixed encoding error on error report.

## 1.2.9: 2018-01-18

### Improvements

  * Added `logical_table_remove` to "may slow commands".

  * Added `--read-timeout` option.

## 1.2.8: 2017-12-04

### Improvements

  * Added `load` support to `collect-query-log` directive.

## 1.2.7: 2017-10-31

### Fixes

  * Fixed incompatible encoding error.

## 1.2.6: 2017-08-16

### Improvements

  * Added `db_directory` variable.

  * Added `disk_usage` response body value normalization support.

## 1.2.5: 2017-08-15

### Improvements

  * Suppressed "thread end" log message.

  * Added error line normalization support for command version 3.

## 1.2.4: 2017-03-27

### Improvements

  * Supported outputting actual file even if the test detects memory
    leaks.

  * Supported unused port dynamically if static port is unavailable.

  * Ignored "thread start" log messages.

  * Supported log with PID.

  * Supported auto chunked `load`.

  * Added `--no-suppress-backtrace` option.

## 1.2.3: 2016-07-19

### Improvements

  * Disabled read time on GDB mode.

  * Supported object literal based response introduced by command version 3.

  * Suppressed omissions from report.

  * Added `generate-series` directive.

  * Added `read-timeout` directive.

  * Added `long-read-timeout` directive.

  * Removed `long-timeout` directive. Use `long-read-timeout` directive instead.

  * Supported `#{base_directory}` expansion in variable value.

  * Supported variable expansion in environment variable value.

  * Supported normalizing plugin path in `object_list`.

## 1.2.2: 2016-05-18

### Improvements

  * Improved shutdown process on error.

## 1.2.1: 2016-05-18

### Fixes

  * Fixed error on shutdown.

## 1.2.0: 2016-05-18

### Improvements

  * Improved shutdown on `--interface stdio`.

## 1.1.9: 2016-05-17

### Improvements

  * Improved debug output.

## 1.1.8: 2016-05-16

### Improvements

  * Added `--debug` option.

## 1.1.7: 2016-05-16

### Improvements

  * Added `timeout` directive.

  * Supported defining environment variable by `#$NAME=VALUE` syntax.

## 1.1.6: 2016-04-27

### Improvements

  * Added `--timeout` option.

## 1.1.5: 2016-04-26

### Fixes

  * [Windows] Fixed a bug that backtrace isn't detected.

## 1.1.4: 2016-04-26

### Improvements

  * Supported Windows.

## 1.1.3: 2016-03-20

### Improvements

  * Added `sleep` directive.
  * Added `collect-query-log` directive.
  * Added `buffered-mark` reporter. You can use it by
    `--runner=buffered-mark`.
  * Improved OS X support.
  * Supported `#{db_path}` in `copy-path` directive argument.
  * Supported SEGV detection on exit.
  * Supported `--columns` option of `load` command.
  * Suppressed omit logs by default. You can enable it by
    `--no-suppress-omit-log`.

## 1.1.2: 2015-07-08

### Improvements

  * Improve HTTP server related error case handlings.
  * Support Valgrind.
  * Added `--stop-on-failure` that stops testing when one test is failed.
  * Support JSONP.
  * Add `add-important-log-levels` directive.
  * Add `remove-important-log-levels` directive.

## 1.1.1: 2015-02-03

### Improvements

  * mark reporter: Show test name on detecting memory leak.
  * Support errno value in system call error message.
  * Support groonga-httpd.
  * Support groonga HTTP server.

## 1.1.0: 2014-10-25

### Improvements

  * Add "load" command to "may slow command" list.

### Fixes

  * Fix a bug that "may slow command" check is broken.

## 1.0.9: 2014-09-28

### Improvements

  * Support multi-line log.
    [GitHub#2] [Reported by Naoya Murakami]

### Thanks

  * Naoya Murakami

## 1.0.8: 2014-08-17

### Fixes

  * Add missing new line in log message. It was a bug that is
    introduced in 1.0.7.

## 1.0.7: 2014-08-16

### Fixes

  * Fix new line handling in bactrace log.
    [groonga-dev,02663] [Reported by Naoya Murakami]

### Thanks

  * Naoya Murakami

## 1.0.6: 2014-08-16

### Improvements

  * Supported normalizing path in error message.
  * Improved backtrace log detection.
    [groonga-dev,02650] [Reported by Naoya Murakami]

### Thanks

  * Naoya Murakami

## 1.0.5: 2014-02-13

### Improvements

  * Supported Ruby 2.0.0 or later.

## 1.0.4: 2013-12-16

### Improvements

  * Supported `groogna-command-parser` gem.

## 1.0.3: 2013-08-12

This is a minor improvement release.

### Improvements

  * Supported XML output.
  * Supported to show the actual result on leaked and not checked status.
  * Supported warning message test.

## 1.0.2: 2012-12-11

This is the release that adds some directive.

### Improvements

  * Used long timeout for `column_create` and `register`.
  * Added `long-timeout` directive.
  * Added `on-error` directive.
  * Added "omit" status and `omit` directive.
  * Aborted a test when a command in it can't be parsed by
    Groonga::Command::Parser.

### Fixes

  * Used stty only when the standard input is tty.

## 1.0.1: 2012-10-15

This has a backward incompatible change. It is directive syntax.

Old:

    # NAME ARGUMENT

New:

    #@NAME ARGUMENT

This change is for easy to debug. Consider about we have a typo in
`NAME`. It is just ignored in old syntax because it is also a comment
line. It is reported in new syntax because it syntax is only for
directive. Grntest can know that user want to use a directive. If
grntest knows that user want to use a directive, grntest can report an
error for an unknown directive name.

### Improvements

* Inverted expected and actual in diff.
* Added memory leak check.
* Documented many features.
* Changed directive syntax.
* Added `copy-path` directive.
* Supported multiple `--test` and `--test-suite` options.
* Added `--database` option.

### Fixes

* Fixed a problem that test report can't be shown for no tests.

## 1.0.0: 2012-08-29

The first release!!!
