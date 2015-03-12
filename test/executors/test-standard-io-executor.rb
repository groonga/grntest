# Copyright (C) 2012-2013  Kouhei Sutou <kou@clear-code.com>
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
require "tempfile"
require "grntest/executors/standard-io-executor"

class TestStandardIOExecutor < Test::Unit::TestCase
  def setup
    input = StringIO.new
    output = StringIO.new
    @context = Grntest::ExecutionContext.new
    @executor = Grntest::Executors::StandardIOExecutor.new(input, output,
                                                           @context)
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
end
