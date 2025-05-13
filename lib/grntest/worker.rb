# Copyright (C) 2012-2018  Kouhei Sutou <kou@clear-code.com>
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

require "grntest/base-result"
require "grntest/test-runner"

module Grntest
  class WorkerResult < BaseResult
    attr_reader :n_tests, :n_passed_tests, :n_leaked_tests
    attr_reader :n_omitted_tests, :n_not_checked_tests
    attr_reader :failed_tests
    def initialize
      super
      @n_tests = 0
      @n_passed_tests = 0
      @n_leaked_tests = 0
      @n_omitted_tests = 0
      @n_not_checked_tests = 0
      @failed_tests = []
    end

    def n_failed_tests
      @failed_tests.size
    end

    def n_leaked_tests
      @n_leaked_tests
    end

    def on_test_finish
      @n_tests += 1
    end

    def on_test_success
      @n_passed_tests += 1
    end

    def on_test_failure(name)
      @failed_tests << name
    end

    def cancel_test_failure(name)
      @failed_tests.delete(name)
    end

    def on_test_leak(name)
      @n_leaked_tests += 1
    end

    def on_test_omission
      @n_omitted_tests += 1
    end

    def on_test_no_check
      @n_not_checked_tests += 1
    end
  end

  class Worker
    attr_reader :id, :tester, :reporter
    attr_reader :suite_name, :test_script_path, :test_name, :status, :result
    def initialize(id, tester, test_suites_result, reporter)
      @id = id
      @tester = tester
      @test_suites_result = test_suites_result
      @reporter = reporter
      @suite_name = nil
      @test_script_path = nil
      @test_name = nil
      @interruptted = false
      @status = "not running"
      @result = WorkerResult.new
    end

    def interrupt
      @interruptted = true
    end

    def interruptted?
      @interruptted
    end

    def run(queue)
      succeeded = true

      @result.measure do
        @reporter.on_worker_start(self)
        loop do
          suite_name, test_script_path, test_name = queue.pop
          break if test_script_path.nil?

          unless @suite_name == suite_name
            @reporter.on_suite_finish(self) if @suite_name
            @suite_name = suite_name
            @reporter.on_suite_start(self)
          end

          unless run_test(test_script_path, test_name)
            succeeded = false
          end

          break if interruptted?

          if @tester.stop_on_failure? and @test_suites_result.have_failure?
            break
          end
        end
        @status = "finished"
        @reporter.on_suite_finish(@suite_name) if @suite_name
        @suite_name = nil
      end
      @reporter.on_worker_finish(self)

      succeeded
    end

    def on_test_start
      @status = "running"
      @test_result = nil
      @reporter.on_test_start(self)
    end

    def on_test_success(result)
      @status = "passed"
      @result.on_test_success
      @reporter.on_test_success(self, result)
    end

    def on_test_failure(result)
      @status = "failed"
      @result.on_test_failure(test_name)
      @reporter.on_test_failure(self, result)
    end

    def on_test_leak(result)
      @status = "leaked(#{result.n_leaked_objects})"
      @result.on_test_leak(test_name)
      @reporter.on_test_leak(self, result)
    end

    def on_test_omission(result)
      @status = "omitted"
      @result.on_test_omission
      if @tester.suppress_omit_log?
        @reporter.on_test_omission_suppressed(self, result)
      else
        @reporter.on_test_omission(self, result)
      end
    end

    def on_test_no_check(result)
      @status = "not checked"
      @result.on_test_no_check
      @reporter.on_test_no_check(self, result)
    end

    def on_test_finish(result)
      @result.on_test_finish
      @reporter.on_test_finish(self, result)
    end

    private
    def run_test(test_script_path, test_name)
      begin
        @test_script_path = test_script_path
        @test_name = test_name

        n = -1
        loop do
          n += 1

          runner = TestRunner.new(@tester, self)
          return true if runner.run
          return false if @result.n_leaked_tests > 0

          if n < @tester.n_retries and not interruptted?
            @result.cancel_test_failure(test_name)
            @test_suites_result.n_total_tests += 1
            next
          end

          return false
        end
      ensure
        @test_script_path = nil
        @test_name = nil
      end
    end
  end
end
