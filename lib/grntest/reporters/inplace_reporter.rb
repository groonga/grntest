# -*- coding: utf-8 -*-
#
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

require "grntest/reporters/base_reporter"

module Grntest
  module Reporters
    class InplaceReporter < BaseReporter
      def initialize(tester)
        super
        @last_redraw_time = Time.now
        @minimum_redraw_interval = 0.1
      end

      def on_start(result)
        @test_suites_result = result
      end

      def on_worker_start(worker)
      end

      def on_suite_start(worker)
        redraw
      end

      def on_test_start(worker)
        redraw
      end

      def on_test_success(worker, result)
        redraw
      end

      def on_test_failure(worker, result)
        redraw do
          report_test(worker, result)
          report_failure(result)
        end
      end

      def on_test_leak(worker, result)
        redraw do
          report_test(worker, result)
          report_marker(result)
          report_actual(result) unless result.checked?
        end
      end

      def on_test_omission(worker, result)
        redraw do
          report_test(worker, result)
          report_actual(result)
        end
      end

      def on_test_no_check(worker, result)
        redraw do
          report_test(worker, result)
          report_actual(result)
        end
      end

      def on_test_finish(worker, result)
        redraw
      end

      def on_suite_finish(worker)
        redraw
      end

      def on_worker_finish(worker)
        redraw
      end

      def on_finish(result)
        draw
        puts
        report_summary(result)
      end

      private
      def draw
        draw_statistics_header_line
        @test_suites_result.workers.each do |worker|
          draw_status_line(worker)
          draw_test_line(worker)
        end
        draw_progress_line
      end

      def draw_statistics_header_line
        puts(statistics_header)
      end

      def draw_status_line(worker)
        clear_line
        left = "[#{colorize(worker.id, worker.result)}] "
        right = " [#{worker.status}]"
        rest_width = @term_width - @current_column
        center_width = rest_width - string_width(left) - string_width(right)
        center = justify(worker.suite_name, center_width)
        puts("#{left}#{center}#{right}")
      end

      def draw_test_line(worker)
        clear_line
        if worker.test_name
          label = "  #{worker.test_name}"
        else
          label = statistics(worker.result)
        end
        puts(justify(label, @term_width))
      end

      def draw_progress_line
        n_done_tests = @test_suites_result.n_tests
        n_total_tests = @test_suites_result.n_total_tests
        if n_total_tests.zero?
          finished_test_ratio = 0.0
        else
          finished_test_ratio = n_done_tests.to_f / n_total_tests
        end

        start_mark = "|"
        finish_mark = "|"
        statistics = " [%3d%%]" % (finished_test_ratio * 100)

        progress_width = @term_width
        progress_width -= start_mark.bytesize
        progress_width -= finish_mark.bytesize
        progress_width -= statistics.bytesize
        finished_mark = "-"
        if n_done_tests == n_total_tests
          progress = colorize(finished_mark * progress_width,
                              @test_suites_result)
        else
          current_mark = ">"
          finished_marks_width = (progress_width * finished_test_ratio).ceil
          finished_marks_width -= current_mark.bytesize
          finished_marks_width = [0, finished_marks_width].max
          progress = finished_mark * finished_marks_width + current_mark
          progress = colorize(progress, @test_suites_result)
          progress << " " * (progress_width - string_width(progress))
        end
        puts("#{start_mark}#{progress}#{finish_mark}#{statistics}")
      end

      def redraw
        synchronize do
          unless block_given?
            return if Time.now - @last_redraw_time < @minimum_redraw_interval
          end
          draw
          if block_given?
            yield
          else
            up_n_lines(n_using_lines)
          end
          @last_redraw_time = Time.now
        end
      end

      def up_n_lines(n)
        print("\e[1A" * n)
      end

      def clear_line
        print(" " * @term_width)
        print("\r")
        reset_current_column
      end

      def n_using_lines
        n_statistics_header_line + n_worker_lines * n_workers + n_progress_lines
      end

      def n_statistics_header_line
        1
      end

      def n_worker_lines
        2
      end

      def n_progress_lines
        1
      end

      def n_workers
        @tester.n_workers
      end
    end
  end
end
