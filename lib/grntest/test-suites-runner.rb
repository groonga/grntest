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

require "thread"

require "grntest/reporters"
require "grntest/worker"
require "grntest/base-result"

module Grntest
  class TestSuitesResult < BaseResult
    attr_accessor :workers
    attr_accessor :n_total_tests
    def initialize
      super
      @workers = []
      @n_total_tests = 0
    end

    def pass_ratio
      n_target_tests = n_tests - n_not_checked_tests
      if n_target_tests.zero?
        0
      else
        (n_passed_tests / n_target_tests.to_f) * 100
      end
    end

    def n_tests
      collect_count(:n_tests)
    end

    def n_passed_tests
      collect_count(:n_passed_tests)
    end

    def n_failed_tests
      collect_count(:n_failed_tests)
    end

    def n_leaked_tests
      collect_count(:n_leaked_tests)
    end

    def n_omitted_tests
      collect_count(:n_omitted_tests)
    end

    def n_not_checked_tests
      collect_count(:n_not_checked_tests)
    end

    def have_failure?
      @workers.any? do |worker|
        worker.result.n_failed_tests > 0 or
          worker.result.n_leaked_tests > 0
      end
    end

    private
    def collect_count(item)
      counts = @workers.collect do |worker|
        worker.result.send(item)
      end
      counts.inject(&:+)
    end
  end

  class TestSuitesRunner
    def initialize(tester)
      @tester = tester
      @reporter = create_reporter
      @result = TestSuitesResult.new
    end

    def run(test_suites)
      succeeded = true

      @result.measure do
        succeeded = run_test_suites(test_suites)
      end
      @reporter.on_finish(@result)

      succeeded
    end

    private
    def run_test_suites(test_suites)
      queue = Queue.new
      test_suites.each do |suite_name, test_script_paths|
        next unless @tester.target_test_suite?(suite_name)
        test_script_paths.each do |test_script_path|
          test_name = test_script_path.basename(".*").to_s
          next unless @tester.target_test?(test_name)
          queue << [suite_name, test_script_path, test_name]
          @result.n_total_tests += 1
        end
      end
      @tester.n_workers.times do
        queue << nil
      end

      workers = []
      @tester.n_workers.times do |i|
        workers << Worker.new(i, @tester, @result, @reporter)
      end
      @result.workers = workers
      @reporter.on_start(@result)

      succeeded = true
      worker_threads = []
      @tester.n_workers.times do |i|
        worker = workers[i]
        worker_threads << Thread.new do
          succeeded = false unless worker.run(queue)
        end
      end

      begin
        worker_threads.each(&:join)
      rescue Interrupt
        workers.each do |worker|
          worker.interrupt
        end
      end

      succeeded
    end

    def create_reporter
      Reporters.create_reporter(@tester)
    end
  end
end
