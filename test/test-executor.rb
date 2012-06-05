# Copyright (C) 2012  Kouhei Sutou <kou@clear-code.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require "stringio"
require "groonga/tester"

class TestExecutor < Test::Unit::TestCase
  def setup
    input = StringIO.new
    output = StringIO.new
    @executor = Groonga::Tester::Executor.new(input, output)
    @context = @executor.context
    @script = Tempfile.new("test-executor")
  end

  private
  def execute(command)
    @script.print(command)
    @script.close
    @executor.execute(Pathname(@script.path))
  end

  class TestComment < self
    def test_disable_logging
      assert_predicate(@context, :logging?)
      execute("# disable-logging")
      assert_not_predicate(@context, :logging?)
    end

    def test_enable_logging
      @context.logging = false
      assert_not_predicate(@context, :logging?)
      execute("# enable-logging")
      assert_predicate(@context, :logging?)
    end

    def test_suggest_create_dataset
      mock(@executor).execute_suggest_create_dataset("shop")
      execute("# suggest-create-dataset shop")
    end
  end

  class TestTranslate < self
    def setup
      @translater = Groonga::Tester::Translater.new
    end

    def test_command
      command = "table_create Site TABLE_HASH_KEY ShortText"
      expected_command =
        "/d/table_create?name=Site&flags=TABLE_HASH_KEY&key_type=ShortText"
      actual_command = translate(command)

      assert_equal(expected_command, actual_command)
    end

    def test_command_with_argument_name
      command = "select --table Sites"
      expected_command = "/d/select?table=Sites"
      actual_command = translate(command)

      assert_equal(expected_command, actual_command)
    end

    def test_command_without_arguments
      command = "dump"
      expected_command = "/d/dump"
      actual_command = translate(command)

      assert_equal(expected_command, actual_command)
    end

    def test_load_command
      command = <<EOF
load --table Sites
[
["_key","uri"],
["groonga","http://groonga.org/"],
["razil","http://razil.jp/"]
]
EOF
      expected_command =
        "/d/load?table=Sites&values=[[\"_key\",\"uri\"]," +
          "[\"groonga\",\"http://groonga.org/\"]," +
          "[\"razil\",\"http://razil.jp/\"]]"
      actual_command = translate(command)

      assert_equal(expected_command, actual_command)
    end

    def test_load_command_with_json_value
      command = <<EOF
load --table Sites
[
{"_key": "ruby", "uri": "http://ruby-lang.org/"}
]
EOF
      expected_command =
        "/d/load?table=Sites&values=[{\"_key\": \"ruby\", " +
          "\"uri\": \"http://ruby-lang.org/\"}]"
      actual_command = translate(command)

      assert_equal(expected_command, actual_command)
    end

    def test_command_with_single_quote
      command = "select Sites --output_columns '_key, uri'"
      expected_command = "/d/select?table=Sites&output_columns=_key,uri"
      actual_command = translate(command)

      assert_equal(expected_command, actual_command)
    end

    def test_command_with_comment
      comment = "#this is comment."
      command = "#{comment}\n" +
        "select --table Sites"
      expected_command = "#{comment}\n" +
        "/d/select?table=Sites"
      actual_command = translate(command)

      assert_equal(expected_command, actual_command)
    end

    private
    def translate(command)
      @translater.translate_command(command)
    end
  end
end
