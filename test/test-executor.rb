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
require "cgi/util"
require "grntest/tester"

class TestExecutor < Test::Unit::TestCase
  def setup
    input = StringIO.new
    output = StringIO.new
    @executor = Grntest::Tester::StandardIOExecutor.new(input, output)
    @context = @executor.context
    @script = Tempfile.new("test-executor")
  end

  private
  def execute(command)
    @script.puts(command)
    @script.close
    @executor.execute(Pathname(@script.path))
  end

  class TestComment < self
    def test_disable_logging
      assert_predicate(@context, :logging?)
      execute("\#@disable-logging")
      assert_not_predicate(@context, :logging?)
    end

    def test_enable_logging
      @context.logging = false
      assert_not_predicate(@context, :logging?)
      execute("\#@enable-logging")
      assert_predicate(@context, :logging?)
    end

    def test_suggest_create_dataset
      mock(@executor).execute_suggest_create_dataset("shop")
      execute("\#@suggest-create-dataset shop")
    end

    def test_enable_ignore_feature_on_error
      assert_not_equal(:omit, @context.on_error)
      execute("\#@on-error omit")
      assert_equal(:omit, @context.on_error)
    end
  end

  class TestCommandFormatConveter < self
    def test_without_argument_name
      command = "table_create Site TABLE_HASH_KEY ShortText"
      arguments = {
        "name" => "Site",
        "flags" => "TABLE_HASH_KEY",
        "key_type" => "ShortText",
      }
      actual_url = convert(command)
      expected_url = build_url("table_create", arguments)

      assert_equal(expected_url, actual_url)
    end

    def test_with_argument_name
      command = "select --table Sites"
      actual_url = convert(command)
      expected_url = build_url("select", "table" => "Sites")

      assert_equal(expected_url, actual_url)
    end

    def test_non_named_argument_after_named_arguement
      command = "table_create --flags TABLE_HASH_KEY --key_type ShortText Site"
      arguments = {
        "flags" => "TABLE_HASH_KEY",
        "key_type" => "ShortText",
        "name" => "Site",
      }
      actual_url = convert(command)
      expected_url = build_url("table_create", arguments)

      assert_equal(expected_url, actual_url)
    end

    def test_without_arguments
      command = "dump"
      actual_url = convert(command)
      expected_url = build_url(command, {})

      assert_equal(expected_url, actual_url)
    end

    def test_load_json_array
      load_command = "load --table Sites"
      load_values = <<EOF
[
["_key","uri"],
["groonga","http://groonga.org/"],
["razil","http://razil.jp/"]
]
EOF
      command = "#{load_command}\n#{load_values}"
      actual_url = convert(command)

      load_values_without_columns =
        '[["groonga","http://groonga.org/"],["razil","http://razil.jp/"]]'
      arguments = {
        "table" => "Sites",
        "columns" => "_key,uri",
        "values" => load_values_without_columns
      }
      expected_url = build_url("load", arguments)

      assert_equal(expected_url, actual_url)
    end

    def test_load_json_object
      load_command = "load --table Sites"
      load_values = <<EOF
[
{"_key": "ruby", "uri": "http://ruby-lang.org/"}
]
EOF
      command = "#{load_command}\n#{load_values}"
      actual_url = convert(command)

      arguments = {
        "table" => "Sites",
        "values" => '[{"_key":"ruby","uri":"http://ruby-lang.org/"}]'
      }
      expected_url = build_url("load", arguments)

      assert_equal(expected_url, actual_url)
    end

    def test_value_single_quote
      command = "select Sites --output_columns '_key, uri'"
      arguments = {
        "table" => "Sites",
        "output_columns" => "_key, uri",
      }
      actual_url = convert(command)
      expected_url = build_url("select", arguments)

      assert_equal(expected_url, actual_url)
    end

    def test_value_double_quote_in_single_quote
      command = "select Sites --filter 'uri @ \"ruby\"'"
      arguments = {
        "table" => "Sites",
        "filter" => "uri @ \"ruby\"",
      }
      actual_url = convert(command)
      expected_url = build_url("select", arguments)

      assert_equal(expected_url, actual_url)
    end

    def test_value_double_quote
      command = "select Sites --output_columns \"_key, uri\""
      arguments = {
        "table" => "Sites",
        "output_columns" => "_key, uri",
      }
      actual_url = convert(command)
      expected_url = build_url("select", arguments)

      assert_equal(expected_url, actual_url)
    end

    private
    def convert(command)
      converter = Grntest::Tester::CommandFormatConverter.new(command)
      converter.to_url
    end

    def build_url(command, named_arguments)
      url = "/d/#{command}"
      query_parameters = []

      sorted_arguments = named_arguments.sort_by do |name, _|
        name
      end
      sorted_arguments.each do |name, argument|
        query_parameters << "#{CGI.escape(name)}=#{CGI.escape(argument)}"
      end
      unless query_parameters.empty?
        url << "?"
        url << query_parameters.join("&")
      end
      url
    end
  end
end
