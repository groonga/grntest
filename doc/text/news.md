# News

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
