# README

## Name

grntest

## Description

Grntest is a testing framework for groonga. You can write a test for
groonga by writing groonga commands and expected result.

## Install

```
% gem install grntest
```

## Basic usage

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
  select                                                   0.3866s [not checked]
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


  tests/sec | tests     | passes    | failures  | leaked    | !checked  |
       2.57 |         1 |         0 |         0 |         0 |         1 |
0% passed in 0.3885s.
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

  tests/sec | tests     | passes    | failures  | leaked    | !checked  |
       5.76 |         1 |         1 |         0 |         0 |         0 |
100% passed in 0.1736s.
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
  select                                                        0.1767s [failed]
================================================================================
--- (expected)
+++ (actual)
@@ -6,5 +6,5 @@
 {"_key": "Bob"}
 ]
 [[0,0.0,0.0],2]
-select Users --query '_key:Alice'
-[[0,0.0,0.0],[[[1],[["_id","UInt32"],["_key","ShortText"]],[1,"Alice"]]]]
+select Users --query '_key:Bob'
+[[0,0.0,0.0],[[[1],[["_id","UInt32"],["_key","ShortText"]],[2,"Bob"]]]]
================================================================================


  tests/sec | tests     | passes    | failures  | leaked    | !checked  |
       4.65 |         1 |         0 |         1 |         0 |         0 |
0% passed in 0.2153s.
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

  tests/sec | tests     | passes    | failures  | leaked    | !checked  |
       6.20 |         1 |         1 |         0 |         0 |         0 |
100% passed in 0.1613s.
```

The test is succeeded again.

## Advanced usage

There are more useful features. They are not needed for normal
users but they are very useful for advanced users.

There are advanced features:

* Comment
* Continuation line
* Directives

### Comment

Groonga supports comment line by `#`.

Example:

```
# This line is comment line.
select Users
```

Grntest also supports the syntax. You can use `#` as comment mark.

### Continuation line

You can split a long line by escaping new line with `\`.

Example:

```
select Users \
  --match_columns name \
  --query Ken
```

The command is processed as the following:

```
select Users  --match_columns name   --query Ken
```

You can make your test readable with this feature.

Groogna doesn't support this feature.

### Directives

Grntest supports directives that control grntest behavior.

Here is directive syntax:

```
#@NAME [ARGUMENTS...]
```

Here are available `NAME` s:

* `disable-logging`
* `enable-logging`
* `suggest-create-dataset`
* `include`

`ARGUMENTS...` are depends on directive. A directive doesn't require
any arguments but a directive requires arguments.

#### `disable-logging`

Usage:

```
#@disable-logging
```

It disables logging exected command and exected result until
`enable-logging` directive is used. It is useful for executing
commands that isn't important for test.

Example:

```
#@disable-logging
load --table Users
[
{"_key": "User1"},
{"_key": "..."},
{"_key": "User9999999"}
]
#@enable-logging

select Users --query _key:User29
```

See also: `enable-logging`

### `enable-logging`

Usage:

```
#@enable-logging
```

It enables logging that is disabled by `disable-logging` directive.

See also: `disable-logging`

### suggest-create-dataset

Usage:

```
#@suggest-create-dataset DATASET_NAME
```

It creates dataset `DATASET_NAME` for suggest feature. It is useful
for testing suggest feature.

Example:

```
#@suggest-create-dataset rurema
load --table event_rurema --each 'suggest_preparer(_id, type, item, sequence, time, pair_rurema)'
[
["sequence", "time", "item", "type"],
["21e80fd5e5bc2126469db1c927b7a48fb3353dd9",1312134098.0,"f",null],
["21e80fd5e5bc2126469db1c927b7a48fb3353dd9",1312134105.0,"er",null],
["21e80fd5e5bc2126469db1c927b7a48fb3353dd9",1312134106.0,"erb",null],
["21e80fd5e5bc2126469db1c927b7a48fb3353dd9",1312134107.0,"erb","submit"]
]
```

See also: `--groonga-suggest-create-dataset` option

### include

Usage

```
#@include SUB_TEST_FILE_PATH
```

It includes `SUB_TEST_FILE_PATH` content. It is useful for sharing
commands by many tests.

You can use `include` in included file. It means that an included file
is processed in the same way as a test file.

If `SUB_TEST_FILE_PATH` is relative path, `SUB_TEST_FILE_PATH` is
found from base directory. Base directory can be specified by
`--base-directory` option.

Example:

init.grn:
```
#@disable-logging
#@include ddl.grn
#@include data.grn
#@enable-logging
```

ddl.grn:
```
table_create Users TABLE_HASH_KEY ShortText
```

data.grn:
```
load --table Users
[
["_key"],
["Alice"],
["Bob"]
]
```

user.test:
```
#@include init.grn
select Users --query _key:Alice
```

See also: `--base-directory` option

## Options

Grntest has many options. You don't need to specify many of them
because they use suitable default values.

This section describes some important options. You can see all options
by `grntest --help`. It contains many usuful features.

### `--test`

### `--exclude-test`

### `--test-suite`

### `--exclude-test-suite`

### `--gdb`

### `--keep-database`

### `--n-workers`

`--n-workers` option is very useful. You can run many test scripts at
once. Tests are finished quickly. You should specify one or more
directories that contain many test scripts. If you have only a test
script, `--n-workers` is not effective.

Here is a sample command line to use `--n-workers`:

```
% grntest --n-workers 4 test/function/suite/suggest
  tests/sec | tests     | passes    | failures  | leaked    | !checked  |
[0]                                                                   [finished]
       9.95 |         5 |         5 |         0 |         0 |         0 |       
[1]                                                                   [finished]
       9.22 |         4 |         4 |         0 |         0 |         0 |       
[2]                                                                   [finished]
       9.11 |         4 |         4 |         0 |         0 |         0 |       
[3]                                                                   [finished]
      10.10 |         5 |         5 |         0 |         0 |         0 |       
|-----------------------------------------------------------------------| [100%]

  tests/sec | tests     | passes    | failures  | leaked    | !checked  |
      34.61 |        18 |        18 |         0 |         0 |         0 |
100% passed in 0.5201s.
```

### `--base-directory`

### `--groonga`

### `--groonga-httpd`

### `--groonga-suggest-create-dataset`

### `--interface`

### `--output-type`

### `--testee`

## Examples

See [test/command/ directory in groonga's
source](https://github.com/groonga/groonga/tree/master/test/command). It
has many test scripts and uses many useful features. They will help you.

## Dependencies

* Ruby 1.9.3

## Mailing list

* English: [groonga-talk@lists.sourceforge.net](https://lists.sourceforge.net/lists/listinfo/groonga-talk)
* Japanese: [groonga-dev@lists.sourceforge.jp](http://lists.sourceforge.jp/mailman/listinfo/groonga-dev)

## Thanks

* ...

## Authors

* Kouhei Sutou \<kou@clear-code.com\>
* Haruka Yoshihara \<yoshihara@clear-code.com\>

## License

GPLv3 or later. See doc/text/gpl-3.0.txt for details.

(Kouhei Sutou has a right to change the license including contributed
patches.)
