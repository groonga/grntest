# -*- coding: utf-8 -*-
#
# Copyright (C) 2012-2015  Kouhei Sutou <kou@clear-code.com>
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

require "grntest/reporters/base-reporter"

module Grntest
  module Reporters
    class MarkReporter < BaseReporter
      def initialize(tester)
        super
      end

      def on_start(result)
      end

      def on_worker_start(worker)
      end

      def on_suite_start(worker)
      end

      def on_test_start(worker)
      end

      def on_test_success(worker, result)
        synchronize do
          report_test_result_mark(".", result)
        end
      end

      def on_test_failure(worker, result)
        synchronize do
          report_test_result_mark("F", result)
          print_new_line
          report_test(worker, result)
          report_failure(result)
        end
      end

      def on_test_leak(worker, result)
        synchronize do
          report_test_result_mark("L(#{result.n_leaked_objects})", result)
          print_new_line
          report_test(worker, result)
          if result.checked?
            report_actual(result)
          else
            report_marker(result)
          end
        end
      end

      def on_test_omission(worker, result)
        synchronize do
          report_test_result_mark("O", result)
          print_new_line
          report_test(worker, result)
          report_actual(result)
        end
      end

      def on_test_no_check(worker, result)
        synchronize do
          report_test_result_mark("N", result)
          print_new_line
          report_test(worker, result)
          report_actual(result)
        end
      end

      def on_test_finish(worker, result)
      end

      def on_suite_finish(worker)
      end

      def on_worker_finish(worker_id)
      end

      def on_finish(result)
        print_new_line
        print_new_line
        report_summary(result)
      end

      private
      def report_test_result_mark(mark, result)
        if @term_width < @current_column + mark.bytesize
          print_new_line
        end
        print_mark(colorize(mark, result))
        if @term_width <= @current_column
          print_new_line
        else
          flush_mark
        end
      end

      def print_new_line
        puts
      end

      def print_mark(mark)
        print(mark)
      end

      def flush_mark
        @output.flush
      end
    end
  end
end
