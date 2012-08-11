# README

## Name

grntest

## Description

Grntest is a testing framework for groonga. You can write a test for groonga by writing groonga commands and expected result.

## Install

```
% gem install grntest
```

## Usage

### Basic usage

Write a test script that extension is `.test`. Here is a sample test
script `select.test`:

```
table_create Users TABLE_HASH_KEY ShortText

load --table Users
[
{"_key": "Alice"},
{"_key": "Bob"}
]

select Users --query '_key:Alice'
```

Run `grntest` with `select.test` as command line argument:

```
% grntest select.test
N
================================================================================
.
  select                                                   0.1667s [not checked]
================================================================================
table_create Users TABLE_HASH_KEY ShortText
[[0,0.0,0.0],true]
load --table Users
[
{"_key": "Alice"},
{"_key": "Bob"}
]
[[0,0.0,0.0],2]
select Users --query '_key:Alice'
[[0,0.0,0.0],[[[1],[["_id","UInt32"],["_key","ShortText"]],[1,"Alice"]]]]
================================================================================


5.96 tests/sec: 1 tests, 0 passes, 0 failures, 1 not checked_tests
0% passed in 0.1678s.
```

It generates `select.actual` file that contains actual result. If it
is expected result, rename it to `select.expected`:

```
% mv select.actual select.expected
```

Run `grntest` again:

```
% grntest select.test
.

6.12 tests/sec: 1 tests, 1 passes, 0 failures, 0 not checked_tests
100% passed in 0.1635s.
```

It compares actual result and content of `select.expected` and
reporots compared result. If they are the same contnet, `grntest`
reports success. If they are not the same content, `grntest` reports
failure and show diff of them.

Change `--query '_key:Alice'` to `--query '_key:Bob`' in
`select.test`:

```
table_create Users TABLE_HASH_KEY ShortText

load --table Users
[
{"_key": "Alice"},
{"_key": "Bob"}
]

select Users --query '_key:Bob'
```

Run `grntest` again:

```
% grntest select.test
F
================================================================================
.
  select                                                        0.1445s [failed]
================================================================================
--- (actual)
+++ (expected)
@@ -6,5 +6,5 @@
 {"_key": "Bob"}
 ]
 [[0,0.0,0.0],2]
-select Users --query '_key:Bob'
-[[0,0.0,0.0],[[[1],[["_id","UInt32"],["_key","ShortText"]],[2,"Bob"]]]]
+select Users --query '_key:Alice'
+[[0,0.0,0.0],[[[1],[["_id","UInt32"],["_key","ShortText"]],[1,"Alice"]]]]
================================================================================


6.68 tests/sec: 1 tests, 0 passes, 1 failures, 0 not checked_tests
0% passed in 0.1497s.
```

It says the expected result that is read from `select.expected` and
the actual result are not same. And the difference of them is shown in
unified diff format. It is helpful to debug the test.

`select.reject` file is generated on failure. It contains the actual
result. If the actual result is the expected result, rename it to
`select.expected`.

```
% mv select.reject select.expected
```

Run `grntest` again:

```
% grntest select.test
.

6.97 tests/sec: 1 tests, 1 passes, 0 failures, 0 not checked_tests
100% passed in 0.1434s.
```

The test is succeeded again.

### Advanced usage

See `grntest --help`. It contains many usuful features.

Some important features are described in this section.

#### `--n-workers`

`--n-workers` option is very useful. You can run many test scripts at
once. Tests are finished quickly. You should specify one or more
directories that contain many test scripts. If you have only a test
script, `--n-workers` is not effective.

Here is a sample command line to use `--n-workers`:

```
% grntest --n-workers 4 test/function/suite/suggest
[0]                                                                   [finished]
  8.60 tests/sec: 4 tests, 4 passes, 0 failures, 0 not checked_tests
[1]                                                                   [finished]
  9.85 tests/sec: 5 tests, 5 passes, 0 failures, 0 not checked_tests
[2]                                                                   [finished]
  8.63 tests/sec: 4 tests, 4 passes, 0 failures, 0 not checked_tests
[3]                                                                   [finished]
  9.68 tests/sec: 5 tests, 5 passes, 0 failures, 0 not checked_tests
|-----------------------------------------------------------------------| [100%]

34.43 tests/sec: 18 tests, 18 passes, 0 failures, 0 not checked_tests
100% passed in 0.5228s.
```

### Examples

See [test/function/ directory in groonga's
source](https://github.com/groonga/groonga/tree/master/test/function). It
has many test scripts and uses many useful features. They will help you.

## Dependencies

* Ruby 1.9.3

### Mailing list

* English: [groonga-talk@lists.sourceforge.net](https://lists.sourceforge.net/lists/listinfo/groonga-talk)
* Japanese: [groonga-dev@lists.sourceforge.jp](http://lists.sourceforge.jp/mailman/listinfo/groonga-dev)

## Thanks

* ...

## Authors

* Kouhei Sutou \<kou@clear-code.com\>

## License

GPLv3 or later. See license/GPL-3 for details.

(Kouhei Sutou has a right to change the license including contributed patches.)
