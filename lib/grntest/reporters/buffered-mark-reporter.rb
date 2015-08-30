# Copyright (C) 2015  Kouhei Sutou <kou@clear-code.com>
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

require "grntest/reporters/mark-reporter"

module Grntest
  module Reporters
    class BufferedMarkReporter < MarkReporter
      def initialize(tester)
        super
        @buffer = ""
      end

      private
      def print_new_line
        puts(@buffer)
        @buffer.clear
      end

      def print_mark(mark)
        increment_current_column(mark)
        @buffer << mark
      end

      def flush_mark
      end
    end
  end
end
