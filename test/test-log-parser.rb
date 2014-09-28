# Copyright (C) 2014  Kouhei Sutou <kou@clear-code.com>
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

require "grntest/log-parser"

class TestLogParser < Test::Unit::TestCase
  def parse(log)
    parser = Grntest::LogParser.new
    entries = []
    parser.parse(log) do |entry|
      entries << entry.to_h
    end
    entries
  end

  sub_test_case("#parse") do
    def test_one_line
      log = "2014-09-27 17:31:53.046467|n| message"
      assert_equal([
                     {
                       :timestamp => "2014-09-27 17:31:53.046467",
                       :log_level => "n",
                       :message   => "message",
                     },
                   ],
                   parse(log))
    end

    def test_one_lines
      log = <<-LOG
2014-09-27 17:31:53.046467|n| notification message
2014-09-27 17:31:54.046467|W| warning message
      LOG
      assert_equal([
                     {
                       :timestamp => "2014-09-27 17:31:53.046467",
                       :log_level => "n",
                       :message   => "notification message",
                     },
                     {
                       :timestamp => "2014-09-27 17:31:54.046467",
                       :log_level => "W",
                       :message   => "warning message",
                     },
                   ],
                   parse(log))
    end


    def test_multi_line
      log = <<-LOG
2014-09-27 17:31:53.046467|n| multi
line message
      LOG
      assert_equal([
                     {
                       :timestamp => "2014-09-27 17:31:53.046467",
                       :log_level => "n",
                       :message   => "multi\nline message",
                     },
                   ],
                   parse(log))
    end
  end
end
