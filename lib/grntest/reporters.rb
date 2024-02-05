# Copyright (C) 2012-2024  Sutou Kouhei <kou@clear-code.com>
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

require "grntest/reporters/benchmark-json-reporter"
require "grntest/reporters/buffered-mark-reporter"
require "grntest/reporters/inplace-reporter"
require "grntest/reporters/mark-reporter"
require "grntest/reporters/progress-reporter"
require "grntest/reporters/stream-reporter"

module Grntest
  module Reporters
    class << self
      def create_reporter(tester)
        case tester.reporter
        when :"benchmark-json"
          BenchmarkJSONReporter.new(tester)
        when :"buffered-mark"
          BufferedMarkReporter.new(tester)
        when :inplace
          InplaceReporter.new(tester)
        when :mark
          MarkReporter.new(tester)
        when :progress
          ProgressReporter.new(tester)
        when :stream
          StreamReporter.new(tester)
        end
      end
    end
  end
end
