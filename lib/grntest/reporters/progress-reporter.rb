# Copyright (C) 2020  Sutou Kouhei <kou@clear-code.com>
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

require "grntest/reporters/inplace-reporter"

module Grntest
  module Reporters
    class ProgressReporter < InplaceReporter
      private
      def draw_statistics_header_line
        puts(statistics_header)
      end

      def draw_status_line(worker)
      end

      def draw_test_line(worker)
      end

      def n_worker_lines
        0
      end
    end
  end
end
