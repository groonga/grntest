# Copyright (C) 2013  Kouhei Sutou <kou@clear-code.com>
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

require "grntest/executors/base-executor"

class TestBaseExecutor < Test::Unit::TestCase
  def setup
    @executor = Grntest::Executors::BaseExecutor.new
    @context = @executor.context
  end

  class TestErrorLog < self
    data("emergency" => "E",
         "alert"     => "A",
         "critical"  => "C",
         "error"     => "e",
         "warning"   => "w")
    def test_important_log_level(level)
      assert_true(@executor.send(:important_log_level?, level))
    end

    data("notice"  => "n",
         "info"    => "i",
         "debug"   => "d",
         "dump"    => "-")
    def test_not_important_log_level(level)
      assert_false(@executor.send(:important_log_level?, level))
    end
  end
end
