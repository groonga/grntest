# News

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
