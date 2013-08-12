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

require "English"
require "optparse"
require "pathname"
require "fileutils"
require "tempfile"
require "shellwords"
require "open-uri"

require "json"
require "msgpack"

require "groonga/command"

require "grntest/version"
require "grntest/error"
require "grntest/reporters"
require "grntest/executors"

module Grntest
  class Tester
    class << self
      def run(argv=nil)
        argv ||= ARGV.dup
        tester = new
        catch do |tag|
          parser = create_option_parser(tester, tag)
          targets = parser.parse!(argv)
          tester.run(*targets)
        end
      end

      private
      def create_option_parser(tester, tag)
        parser = OptionParser.new
        parser.banner += " TEST_FILE_OR_DIRECTORY..."

        parser.on("--groonga=COMMAND",
                  "Use COMMAND as groonga command",
                  "(#{tester.groonga})") do |command|
          tester.groonga = command
        end

        parser.on("--groonga-httpd=COMMAND",
                  "Use COMMAND as groonga-httpd command for groonga-httpd tests",
                  "(#{tester.groonga_httpd})") do |command|
          tester.groonga_httpd = command
        end

        parser.on("--groonga-suggest-create-dataset=COMMAND",
                  "Use COMMAND as groonga_suggest_create_dataset command",
                  "(#{tester.groonga_suggest_create_dataset})") do |command|
          tester.groonga_suggest_create_dataset = command
        end

        available_interfaces = [:stdio, :http]
        available_interface_labels = available_interfaces.join(", ")
        parser.on("--interface=INTERFACE", available_interfaces,
                  "Use INTERFACE for communicating groonga",
                  "[#{available_interface_labels}]",
                  "(#{tester.interface})") do |interface|
          tester.interface = interface
        end

        available_output_types = ["json", "msgpack"]
        available_output_type_labels = available_output_types.join(", ")
        parser.on("--output-type=TYPE", available_output_types,
                  "Use TYPE as the output type",
                  "[#{available_output_type_labels}]",
                  "(#{tester.output_type})") do |type|
          tester.output_type = type
        end

        available_testees = ["groonga", "groonga-httpd"]
        available_testee_labels = available_testees.join(", ")
        parser.on("--testee=TESTEE", available_testees,
                  "Test against TESTEE",
                  "[#{available_testee_labels}]",
                  "(#{tester.testee})") do |testee|
          tester.testee = testee
          if tester.testee == "groonga-httpd"
            tester.interface = :http
          end
        end

        parser.on("--base-directory=DIRECTORY",
                  "Use DIRECTORY as a base directory of relative path",
                  "(#{tester.base_directory})") do |directory|
          tester.base_directory = Pathname(directory)
        end

        parser.on("--database=PATH",
                  "Use existing database at PATH " +
                    "instead of creating a new database",
                  "(creating a new database)") do |path|
          tester.database_path = path
        end

        parser.on("--diff=DIFF",
                  "Use DIFF as diff command",
                  "(#{tester.diff})") do |diff|
          tester.diff = diff
          tester.diff_options.clear
        end

        diff_option_is_specified = false
        parser.on("--diff-option=OPTION",
                  "Use OPTION as diff command",
                  "(#{tester.diff_options.join(' ')})") do |option|
          tester.diff_options.clear if diff_option_is_specified
          tester.diff_options << option
          diff_option_is_specified = true
        end

        available_reporters = [:mark, :stream, :inplace]
        available_reporter_labels = available_reporters.join(", ")
        parser.on("--reporter=REPORTER", available_reporters,
                  "Report test result by REPORTER",
                  "[#{available_reporter_labels}]",
                  "(auto)") do |reporter|
          tester.reporter = reporter
        end

        parser.on("--test=NAME",
                  "Run only test that name is NAME",
                  "If NAME is /.../, NAME is treated as regular expression",
                  "This option can be used multiple times") do |name|
          tester.test_patterns << parse_name_or_pattern(name)
        end

        parser.on("--test-suite=NAME",
                  "Run only test suite that name is NAME",
                  "If NAME is /.../, NAME is treated as regular expression",
                  "This option can be used multiple times") do |name|
          tester.test_suite_patterns << parse_name_or_pattern(name)
        end

        parser.on("--exclude-test=NAME",
                  "Exclude test that name is NAME",
                  "If NAME is /.../, NAME is treated as regular expression",
                  "This option can be used multiple times") do |name|
          tester.exclude_test_patterns << parse_name_or_pattern(name)
        end

        parser.on("--exclude-test-suite=NAME",
                  "Exclude test suite that name is NAME",
                  "If NAME is /.../, NAME is treated as regular expression",
                  "This option can be used multiple times") do |name|
          tester.exclude_test_suite_patterns << parse_name_or_pattern(name)
        end

        parser.on("--n-workers=N", Integer,
                  "Use N workers to run tests") do |n|
          tester.n_workers = n
        end

        parser.on("--gdb[=COMMAND]",
                  "Run groonga on gdb and use COMMAND as gdb",
                  "(#{tester.default_gdb})") do |command|
          tester.gdb = command || tester.default_gdb
        end

        parser.on("--[no-]keep-database",
                  "Keep used database for debug after test is finished",
                  "(#{tester.keep_database?})") do |boolean|
          tester.keep_database = boolean
        end

        parser.on("--output=OUTPUT",
                  "Output to OUTPUT",
                  "(stdout)") do |output|
          tester.output = File.open(output, "w:ascii-8bit")
        end

        parser.on("--[no-]use-color",
                  "Enable colorized output",
                  "(auto)") do |use_color|
          tester.use_color = use_color
        end

        parser.on("--version",
                  "Show version and exit") do
          puts(VERSION)
          throw(tag, true)
        end

        parser
      end

      def parse_name_or_pattern(name)
        if /\A\/(.+)\/\z/ =~ name
          Regexp.new($1, Regexp::IGNORECASE)
        else
          name
        end
      end
    end

    attr_accessor :groonga, :groonga_httpd, :groonga_suggest_create_dataset
    attr_accessor :interface, :output_type, :testee
    attr_accessor :base_directory, :database_path, :diff, :diff_options
    attr_accessor :n_workers
    attr_accessor :output
    attr_accessor :gdb, :default_gdb
    attr_writer :reporter, :keep_database, :use_color
    attr_reader :test_patterns, :test_suite_patterns
    attr_reader :exclude_test_patterns, :exclude_test_suite_patterns
    def initialize
      @groonga = "groonga"
      @groonga_httpd = "groonga-httpd"
      @groonga_suggest_create_dataset = "groonga-suggest-create-dataset"
      @interface = :stdio
      @output_type = "json"
      @testee = "groonga"
      @base_directory = Pathname(".")
      @database_path = nil
      @reporter = nil
      @n_workers = 1
      @output = $stdout
      @keep_database = false
      @use_color = nil
      @test_patterns = []
      @test_suite_patterns = []
      @exclude_test_patterns = []
      @exclude_test_suite_patterns = []
      detect_suitable_diff
      initialize_debuggers
    end

    def run(*targets)
      succeeded = true
      return succeeded if targets.empty?

      test_suites = load_tests(*targets)
      run_test_suites(test_suites)
    end

    def reporter
      if @reporter.nil?
        if @n_workers == 1
          :mark
        else
          :inplace
        end
      else
        @reporter
      end
    end

    def keep_database?
      @keep_database
    end

    def use_color?
      if @use_color.nil?
        @use_color = guess_color_availability
      end
      @use_color
    end

    def target_test?(test_name)
      selected_test?(test_name) and not excluded_test?(test_name)
    end

    def selected_test?(test_name)
      return true if @test_patterns.empty?
      @test_patterns.any? do |pattern|
        pattern === test_name
      end
    end

    def excluded_test?(test_name)
      @exclude_test_patterns.any? do |pattern|
        pattern === test_name
      end
    end

    def target_test_suite?(test_suite_name)
      selected_test_suite?(test_suite_name) and
        not excluded_test_suite?(test_suite_name)
    end

    def selected_test_suite?(test_suite_name)
      return true if @test_suite_patterns.empty?
      @test_suite_patterns.any? do |pattern|
        pattern === test_suite_name
      end
    end

    def excluded_test_suite?(test_suite_name)
      @exclude_test_suite_patterns.any? do |pattern|
        pattern === test_suite_name
      end
    end

    private
    def load_tests(*targets)
      default_group_name = "."
      tests = {default_group_name => []}
      targets.each do |target|
        target_path = Pathname(target)
        next unless target_path.exist?
        if target_path.directory?
          load_tests_under_directory(tests, target_path)
        else
          tests[default_group_name] << target_path
        end
      end
      tests
    end

    def load_tests_under_directory(tests, test_directory_path)
      test_file_paths = Pathname.glob(test_directory_path + "**" + "*.test")
      test_file_paths.each do |test_file_path|
        directory_path = test_file_path.dirname
        directory = directory_path.relative_path_from(test_directory_path).to_s
        tests[directory] ||= []
        tests[directory] << test_file_path
      end
    end

    def run_test_suites(test_suites)
      runner = TestSuitesRunner.new(self)
      runner.run(test_suites)
    end

    def detect_suitable_diff
      if command_exist?("cut-diff")
        @diff = "cut-diff"
        @diff_options = ["--context-lines", "10"]
      else
        @diff = "diff"
        @diff_options = ["-u"]
      end
    end

    def initialize_debuggers
      @gdb = nil
      @default_gdb = "gdb"
    end

    def command_exist?(name)
      ENV["PATH"].split(File::PATH_SEPARATOR).each do |path|
        absolute_path = File.join(path, name)
        return true if File.executable?(absolute_path)
      end
      false
    end

    def guess_color_availability
      return false unless @output.tty?
      case ENV["TERM"]
      when /term(?:-(?:256)?color)?\z/, "screen"
        true
      else
        return true if ENV["EMACS"] == "t"
        false
      end
    end

    class Result
      attr_accessor :elapsed_time
      def initialize
        @elapsed_time = 0
      end

      def measure
        start_time = Time.now
        yield
      ensure
        @elapsed_time = Time.now - start_time
      end
    end

    class WorkerResult < Result
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

      def on_test_finish
        @n_tests += 1
      end

      def on_test_success
        @n_passed_tests += 1
      end

      def on_test_failure(name)
        @failed_tests << name
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
      attr_reader :id, :tester, :test_suites_rusult, :reporter
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
          catch do |tag|
            loop do
              suite_name, test_script_path, test_name = queue.pop
              break if test_script_path.nil?

              unless @suite_name == suite_name
                @reporter.on_suite_finish(self) if @suite_name
                @suite_name = suite_name
                @reporter.on_suite_start(self)
              end
              @test_script_path = test_script_path
              @test_name = test_name
              runner = TestRunner.new(@tester, self)
              succeeded = false unless runner.run

              break if interruptted?
            end
            @status = "finished"
            @reporter.on_suite_finish(@suite_name) if @suite_name
            @suite_name = nil
          end
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
        @reporter.on_test_omission(self, result)
      end

      def on_test_no_check(result)
        @status = "not checked"
        @result.on_test_no_check
        @reporter.on_test_no_check(self, result)
      end

      def on_test_finish(result)
        @result.on_test_finish
        @reporter.on_test_finish(self, result)
        @test_script_path = nil
        @test_name = nil
      end
    end

    class TestSuitesResult < Result
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
        Grntest::Reporters.create_repoter(@tester)
      end
    end

    class TestResult < Result
      attr_accessor :worker_id, :test_name
      attr_accessor :expected, :actual, :n_leaked_objects
      attr_writer :omitted
      def initialize(worker)
        super()
        @worker_id = worker.id
        @test_name = worker.test_name
        @actual = nil
        @expected = nil
        @n_leaked_objects = 0
        @omitted = false
      end

      def status
        return :omitted if omitted?

        if @expected
          if @actual == @expected
            if leaked?
              :leaked
            else
              :success
            end
          else
            :failure
          end
        else
          if leaked?
            :leaked
          else
            :not_checked
          end
        end
      end

      def omitted?
        @omitted
      end

      def leaked?
        not @n_leaked_objects.zero?
      end

      def checked?
        not @expected.nil?
      end
    end

    class TestRunner
      MAX_N_COLUMNS = 79

      def initialize(tester, worker)
        @tester = tester
        @worker = worker
        @max_n_columns = MAX_N_COLUMNS
        @id = nil
      end

      def run
        succeeded = true

        @worker.on_test_start
        result = TestResult.new(@worker)
        result.measure do
          execute_groonga_script(result)
        end
        normalize_actual_result(result)
        result.expected = read_expected_result
        case result.status
        when :success
          @worker.on_test_success(result)
          remove_reject_file
        when :failure
          @worker.on_test_failure(result)
          output_reject_file(result.actual)
          succeeded = false
        when :leaked
          @worker.on_test_leak(result)
          succeeded = false
        when :omitted
          @worker.on_test_omission(result)
        else
          @worker.on_test_no_check(result)
          output_actual_file(result.actual)
        end
        @worker.on_test_finish(result)

        succeeded
      end

      private
      def execute_groonga_script(result)
        create_temporary_directory do |directory_path|
          if @tester.database_path
            db_path = Pathname(@tester.database_path).expand_path
          else
            db_dir = directory_path + "db"
            FileUtils.mkdir_p(db_dir.to_s)
            db_path = db_dir + "db"
          end
          context = Execution::Context.new
          context.temporary_directory_path = directory_path
          context.db_path = db_path
          context.base_directory = @tester.base_directory.expand_path
          context.groonga_suggest_create_dataset =
            @tester.groonga_suggest_create_dataset
          context.output_type = @tester.output_type
          run_groonga(context) do |executor|
            executor.execute(test_script_path)
          end
          check_memory_leak(context)
          result.omitted = context.omitted?
          result.actual = context.result
        end
      end

      def create_temporary_directory
        path = "tmp/grntest"
        path << ".#{@worker.id}" if @tester.n_workers > 1
        FileUtils.rm_rf(path, :secure => true)
        FileUtils.mkdir_p(path)
        begin
          yield(Pathname(path).expand_path)
        ensure
          if @tester.keep_database? and File.exist?(path)
            FileUtils.rm_rf(keep_database_path, :secure => true)
            FileUtils.mv(path, keep_database_path)
          else
            FileUtils.rm_rf(path, :secure => true)
          end
        end
      end

      def keep_database_path
        test_script_path.to_s.gsub(/\//, ".")
      end

      def run_groonga(context, &block)
        unless @tester.database_path
          create_empty_database(context.db_path.to_s)
        end

        catch do |tag|
          context.abort_tag = tag
          case @tester.interface
          when :stdio
            run_groonga_stdio(context, &block)
          when :http
            run_groonga_http(context, &block)
          end
        end
      end

      def run_groonga_stdio(context)
        pid = nil
        begin
          open_pipe do |input_read, input_write, output_read, output_write|
            groonga_input = input_write
            groonga_output = output_read

            input_fd = input_read.to_i
            output_fd = output_write.to_i
            env = {}
            spawn_options = {
              input_fd => input_fd,
              output_fd => output_fd
            }
            command_line = groonga_command_line(context, spawn_options)
            command_line += [
              "--input-fd", input_fd.to_s,
              "--output-fd", output_fd.to_s,
              context.relative_db_path.to_s,
            ]
            pid = Process.spawn(env, *command_line, spawn_options)
            executor = StandardIOExecutor.new(groonga_input,
                                              groonga_output,
                                              context)
            executor.ensure_groonga_ready
            yield(executor)
          end
        ensure
          Process.waitpid(pid) if pid
        end
      end

      def open_pipe
        IO.pipe("ASCII-8BIT") do |input_read, input_write|
          IO.pipe("ASCII-8BIT") do |output_read, output_write|
            yield(input_read, input_write, output_read, output_write)
          end
        end
      end

      def command_command_line(command, context, spawn_options)
        command_line = []
        if @tester.gdb
          if libtool_wrapper?(command)
            command_line << find_libtool(command)
            command_line << "--mode=execute"
          end
          command_line << @tester.gdb
          gdb_command_path = context.temporary_directory_path + "groonga.gdb"
          File.open(gdb_command_path, "w") do |gdb_command|
            gdb_command.puts(<<-EOC)
break main
run
print chdir("#{context.temporary_directory_path}")
EOC
          end
          command_line << "--command=#{gdb_command_path}"
          command_line << "--quiet"
          command_line << "--args"
        else
          spawn_options[:chdir] = context.temporary_directory_path.to_s
        end
        command_line << command
        command_line
      end

      def groonga_command_line(context, spawn_options)
        command_line = command_command_line(@tester.groonga, context,
                                            spawn_options)
        command_line << "--log-path=#{context.log_path}"
        command_line << "--working-directory=#{context.temporary_directory_path}"
        command_line
      end

      def libtool_wrapper?(command)
        return false unless File.exist?(command)
        File.open(command, "r") do |command_file|
          first_line = command_file.gets
          first_line.start_with?("#!")
        end
      end

      def find_libtool(command)
        command_path = Pathname.new(command)
        directory = command_path.dirname
        until directory.root?
          libtool = directory + "libtool"
          return libtool.to_s if libtool.executable?
          directory = directory.parent
        end
        "libtool"
      end

      def run_groonga_http(context)
        host = "127.0.0.1"
        port = 50041 + @worker.id
        pid_file_path = context.temporary_directory_path + "groonga.pid"

        env = {}
        spawn_options = {}
        command_line = groonga_http_command(host, port, pid_file_path, context,
                                            spawn_options)
        pid = nil
        begin
          pid = Process.spawn(env, *command_line, spawn_options)
          begin
            executor = HTTPExecutor.new(host, port, context)
            begin
              executor.ensure_groonga_ready
            rescue
              if Process.waitpid(pid, Process::WNOHANG)
                pid = nil
                raise
              end
              raise unless @tester.gdb
              retry
            end
            yield(executor)
          ensure
            executor.send_command("shutdown")
            wait_groonga_http_shutdown(pid_file_path)
          end
        ensure
          Process.waitpid(pid) if pid
        end
      end

      def wait_groonga_http_shutdown(pid_file_path)
        total_sleep_time = 0
        sleep_time = 0.1
        while pid_file_path.exist?
          sleep(sleep_time)
          total_sleep_time += sleep_time
          break if total_sleep_time > 1.0
        end
      end

      def groonga_http_command(host, port, pid_file_path, context, spawn_options)
        case @tester.testee
        when "groonga"
          command_line = groonga_command_line(context, spawn_options)
          command_line += [
            "--pid-path", pid_file_path.to_s,
            "--bind-address", host,
            "--port", port.to_s,
            "--protocol", "http",
            "-s",
            context.relative_db_path.to_s,
          ]
        when "groonga-httpd"
          command_line = command_command_line(@tester.groonga_httpd, context,
                                              spawn_options)
          config_file_path = create_config_file(context, host, port,
                                                pid_file_path)
          command_line += [
            "-c", config_file_path.to_s,
            "-p", "#{context.temporary_directory_path}/",
          ]
        end
        command_line
      end

      def create_config_file(context, host, port, pid_file_path)
        config_file_path =
          context.temporary_directory_path + "groonga-httpd.conf"
        config_file_path.open("w") do |config_file|
            config_file.puts(<<EOF)
daemon off;
master_process off;
worker_processes 1;
working_directory #{context.temporary_directory_path};
error_log groonga-httpd-access.log;
pid #{pid_file_path};
events {
     worker_connections 1024;
}

http {
     server {
             access_log groonga-httpd-access.log;
             listen #{port};
             server_name #{host};
             location /d/ {
                     groonga_database #{context.relative_db_path};
                     groonga on;
            }
     }
}
EOF
        end
        config_file_path
      end

      def create_empty_database(db_path)
        output_fd = Tempfile.new("create-empty-database")
        create_database_command = [
          @tester.groonga,
          "--output-fd", output_fd.to_i.to_s,
          "-n", db_path,
          "shutdown"
        ]
        system(*create_database_command)
        output_fd.close(true)
      end

      def normalize_actual_result(result)
        normalized_result = ""
        result.actual.each do |tag, content, options|
          case tag
          when :input
            normalized_result << content
          when :output
            normalized_result << normalize_output(content, options)
          when :error
            normalized_result << normalize_raw_content(content)
          when :n_leaked_objects
            result.n_leaked_objects = content
          end
        end
        result.actual = normalized_result
      end

      def normalize_raw_content(content)
        "#{content}\n".force_encoding("ASCII-8BIT")
      end

      def normalize_output(content, options)
        type = options[:type]
        case type
        when "json", "msgpack"
          status = nil
          values = nil
          begin
            status, *values = ResponseParser.parse(content.chomp, type)
          rescue ParseError
            return $!.message
          end
          normalized_status = normalize_status(status)
          normalized_output_content = [normalized_status, *values]
          normalized_output = JSON.generate(normalized_output_content)
          if normalized_output.bytesize > @max_n_columns
            normalized_output = JSON.pretty_generate(normalized_output_content)
          end
          normalize_raw_content(normalized_output)
        when "xml"
          normalized_xml = normalize_output_xml(content, options)
          normalize_raw_content(normalized_xml)
        else
          normalize_raw_content(content)
        end
      end

      def normalize_output_xml(content, options)
        content.sub(/^<RESULT .+?>/) do |result|
          result.gsub(/( (?:UP|ELAPSED))="\d+\.\d+(?:e[+-]?\d+)?"/, '\1="0.0"')
        end
      end

      def normalize_status(status)
        return_code, started_time, elapsed_time, *rest = status
        _ = started_time = elapsed_time # for suppress warnings
        if return_code.zero?
          [0, 0.0, 0.0]
        else
          message, backtrace = rest
          _ = backtrace # for suppress warnings
          [[return_code, 0.0, 0.0], message]
        end
      end

      def test_script_path
        @worker.test_script_path
      end

      def have_extension?
        not test_script_path.extname.empty?
      end

      def related_file_path(extension)
        path = Pathname(test_script_path.to_s.gsub(/\.[^.]+\z/, ".#{extension}"))
        return nil if test_script_path == path
        path
      end

      def read_expected_result
        return nil unless have_extension?
        result_path = related_file_path("expected")
        return nil if result_path.nil?
        return nil unless result_path.exist?
        result_path.open("r:ascii-8bit") do |result_file|
          result_file.read
        end
      end

      def remove_reject_file
        return unless have_extension?
        reject_path = related_file_path("reject")
        return if reject_path.nil?
        FileUtils.rm_rf(reject_path.to_s, :secure => true)
      end

      def output_reject_file(actual_result)
        output_actual_result(actual_result, "reject")
      end

      def output_actual_file(actual_result)
        output_actual_result(actual_result, "actual")
      end

      def output_actual_result(actual_result, suffix)
        result_path = related_file_path(suffix)
        return if result_path.nil?
        result_path.open("w:ascii-8bit") do |result_file|
          result_file.print(actual_result)
        end
      end

      def check_memory_leak(context)
        context.log.each_line do |line|
          timestamp, log_level, message = line.split(/\|\s*/, 3)
          _ = timestamp # suppress warning
          next unless /^grn_fin \((\d+)\)$/ =~ message
          n_leaked_objects = $1.to_i
          next if n_leaked_objects.zero?
          context.result << [:n_leaked_objects, n_leaked_objects, {}]
        end
      end
    end
  end
end
