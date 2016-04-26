# Copyright (C) 2016  Kouhei Sutou <kou@clear-code.com>
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

require "diff/lcs"
require "diff/lcs/hunk"

module Grntest
  class DiffReporter
    def initialize(expected, actual)
      @expected = expected
      @actual = actual
    end

    def report
      expected_lines = @expected.lines.collect(&:chomp)
      actual_lines = @actual.lines.collect(&:chomp)
      diffs = Diff::LCS.diff(expected_lines,
                             actual_lines)
      return if diffs.empty?

      report_expected_label("(expected)")
      report_actual_label("(actual)")

      context_n_lines = 3
      previous_hunk = nil
      file_length_diff = 0
      diffs.each do |diff|
        begin
          hunk = Diff::LCS::Hunk.new(expected_lines,
                                     actual_lines,
                                     diff,
                                     context_n_lines,
                                     file_length_diff)
          next if previous_hunk.nil?
          next if hunk.merge(previous_hunk)

          report_hunk(previous_hunk)
        ensure
          previous_hunk = hunk
        end
      end
      report_hunk(previous_hunk)
    end

    private
    def expected_mark
      "-"
    end

    def actual_mark
      "+"
    end

    def report_expected_label(content)
      puts("#{expected_mark * 3} #{content}")
    end

    def report_actual_label(content)
      puts("#{actual_mark * 3} #{content}")
    end

    def report_hunk(hunk)
      puts(hunk.diff(:unified))
    end
  end
end
