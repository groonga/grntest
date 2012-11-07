# -*- coding: utf-8 -*-
#
# Copyright (C) 2012  Kouhei Sutou <kou@clear-code.com>
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
require "cgi/util"

require "json"
require "msgpack"

require "grntest/version"

module Grntest
  class Tester
    class Error < StandardError
    end

    class NotExist < Error
      attr_reader :path
      def initialize(path)
        @path = path
        super("<#{path}> doesn't exist.")
      end
    end

    class ParseError < Error
      attr_reader :type, :content, :reason
      def initialize(type, content, reason)
        @type = type
        @content = content
        @reason = reason
        super("failed to parse <#{@type}> content: #{reason}: <#{content}>")
      end
    end

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
      attr_reader :n_not_checked_tests
      attr_reader :failed_tests
      def initialize
        super
        @n_tests = 0
        @n_passed_tests = 0
        @n_leaked_tests = 0
        @n_not_checked_tests = 0
        @failed_tests = []
      end

      def n_failed_tests
        @failed_tests.size
      end

      def test_finished
        @n_tests += 1
      end

      def test_passed
        @n_passed_tests += 1
      end

      def test_failed(name)
        @failed_tests << name
      end

      def test_leaked(name)
        @n_leaked_tests += 1
      end

      def test_not_checked
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
          @reporter.start_worker(self)
          catch do |tag|
            loop do
              suite_name, test_script_path, test_name = queue.pop
              break if test_script_path.nil?

              unless @suite_name == suite_name
                @reporter.finish_suite(self) if @suite_name
                @suite_name = suite_name
                @reporter.start_suite(self)
              end
              @test_script_path = test_script_path
              @test_name = test_name
              runner = TestRunner.new(@tester, self)
              succeeded = false unless runner.run

              break if interruptted?
            end
            @status = "finished"
            @reporter.finish_suite(@suite_name) if @suite_name
            @suite_name = nil
          end
        end
        @reporter.finish_worker(self)

        succeeded
      end

      def start_test
        @status = "running"
        @test_result = nil
        @reporter.start_test(self)
      end

      def pass_test(result)
        @status = "passed"
        @result.test_passed
        @reporter.pass_test(self, result)
      end

      def fail_test(result)
        @status = "failed"
        @result.test_failed(test_name)
        @reporter.fail_test(self, result)
      end

      def leaked_test(result)
        @status = "leaked(#{result.n_leaked_objects})"
        @result.test_leaked(test_name)
        @reporter.leaked_test(self, result)
      end

      def not_checked_test(result)
        @status = "not checked"
        @result.test_not_checked
        @reporter.not_checked_test(self, result)
      end

      def finish_test(result)
        @result.test_finished
        @reporter.finish_test(self, result)
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
        @reporter.finish(@result)

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
        @reporter.start(@result)

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
        case @tester.reporter
        when :mark
          MarkReporter.new(@tester)
        when :stream
          StreamReporter.new(@tester)
        when :inplace
          InplaceReporter.new(@tester)
        end
      end
    end

    class TestResult < Result
      attr_accessor :worker_id, :test_name
      attr_accessor :expected, :actual, :n_leaked_objects
      def initialize(worker)
        super()
        @worker_id = worker.id
        @test_name = worker.test_name
        @actual = nil
        @expected = nil
        @n_leaked_objects = 0
      end

      def status
        if @expected
          if @actual == @expected
            if @n_leaked_objects.zero?
              :success
            else
              :leaked
            end
          else
            :failure
          end
        else
          if @n_leaked_objects.zero?
            :not_checked
          else
            :leaked
          end
        end
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

        @worker.start_test
        result = TestResult.new(@worker)
        result.measure do
          result.actual = execute_groonga_script
        end
        normalize_actual_result(result)
        result.expected = read_expected_result
        case result.status
        when :success
          @worker.pass_test(result)
          remove_reject_file
        when :failure
          @worker.fail_test(result)
          output_reject_file(result.actual)
          succeeded = false
        when :leaked
          @worker.leaked_test(result)
          succeeded = false
        else
          @worker.not_checked_test(result)
          output_actual_file(result.actual)
        end
        @worker.finish_test(result)

        succeeded
      end

      private
      def execute_groonga_script
        create_temporary_directory do |directory_path|
          if @tester.database_path
            db_path = Pathname(@tester.database_path).expand_path
          else
            db_dir = directory_path + "db"
            FileUtils.mkdir_p(db_dir.to_s)
            db_path = db_dir + "db"
          end
          context = Executor::Context.new
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
          context.result
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

        case @tester.interface
        when :stdio
          run_groonga_stdio(context, &block)
        when :http
          run_groonga_http(context, &block)
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
            status, *values = parse_result(content.chomp, type)
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
        else
          normalize_raw_content(content)
        end
      end

      def parse_result(result, type)
        case type
        when "json"
          begin
            JSON.parse(result)
          rescue JSON::ParserError
            raise ParseError.new(type, result, $!.message)
          end
        when "msgpack"
          begin
            MessagePack.unpack(result.chomp)
          rescue MessagePack::UnpackError, NoMemoryError
            raise ParseError.new(type, result, $!.message)
          end
        else
          raise ParseError.new(type, result, "unknown type")
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

    class Executor
      class Context
        attr_writer :logging
        attr_accessor :base_directory, :temporary_directory_path, :db_path
        attr_accessor :groonga_suggest_create_dataset
        attr_accessor :result
        attr_accessor :output_type
        def initialize
          @logging = true
          @base_directory = Pathname(".")
          @temporary_directory_path = Pathname("tmp")
          @db_path = Pathname("db")
          @groonga_suggest_create_dataset = "groonga-suggest-create-dataset"
          @n_nested = 0
          @result = []
          @output_type = "json"
          @log = nil
        end

        def logging?
          @logging
        end

        def execute
          @n_nested += 1
          yield
        ensure
          @n_nested -= 1
        end

        def top_level?
          @n_nested == 1
        end

        def log_path
          @temporary_directory_path + "groonga.log"
        end

        def log
          @log ||= File.open(log_path.to_s, "a+")
        end

        def relative_db_path
          @db_path.relative_path_from(@temporary_directory_path)
        end
      end

      attr_reader :context
      def initialize(context=nil)
        @loading = false
        @pending_command = ""
        @pending_load_command = nil
        @current_command_name = nil
        @output_type = nil
        @context = context || Context.new
      end

      def execute(script_path)
        unless script_path.exist?
          raise NotExist.new(script_path)
        end

        @context.execute do
          script_path.open("r:ascii-8bit") do |script_file|
            script_file.each_line do |line|
              begin
                if @loading
                  execute_line_on_loading(line)
                else
                  execute_line_with_continuation_line_support(line)
                end
              rescue Error
                line_info = "#{script_path}:#{script_file.lineno}:#{line.chomp}"
                log_error("#{line_info}: #{$!.message}")
                raise unless @context.top_level?
              end
            end
          end
        end

        @context.result
      end

      private
      def execute_line_on_loading(line)
        log_input(line)
        @pending_load_command << line
        if line == "]\n"
          execute_command(@pending_load_command)
          @pending_load_command = nil
          @loading = false
        end
      end

      def execute_line_with_continuation_line_support(line)
        if /\\$/ =~ line
          @pending_command << $PREMATCH
        else
          if @pending_command.empty?
            execute_line(line)
          else
            @pending_command << line
            execute_line(@pending_command)
            @pending_command = ""
          end
        end
      end

      def execute_line(line)
        case line
        when /\A\#@/
          directive_content = $POSTMATCH
          execute_directive(line, directive_content)
        when /\A\s*\z/
          # do nothing
        when /\A\s*\#/
          # ignore comment
        else
          execute_command_line(line)
        end
      end

      def resolve_path(path)
        if path.relative?
          @context.base_directory + path
        else
          path
        end
      end

      def execute_directive_suggest_create_dataset(line, content, options)
        dataset_name = options.first
        if dataset_name.nil?
          log_input(line)
          log_error("#|e| [suggest-create-dataset] dataset name is missing")
          return
        end
        execute_suggest_create_dataset(dataset_name)
      end

      def execute_directive_include(line, content, options)
        path = options.first
        if path.nil?
          log_input(line)
          log_error("#|e| [include] path is missing")
          return
        end
        execute_script(Pathname(path))
      end

      def execute_directive_copy_path(line, content, options)
        source, destination, = options
        if source.nil? or destination.nil?
          log_input(line)
          if source.nil?
            log_error("#|e| [copy-path] source is missing")
          end
          if destiantion.nil?
            log_error("#|e| [copy-path] destination is missing")
          end
          return
        end
        source = resolve_path(Pathname(source))
        destination = resolve_path(Pathname(destination))
        FileUtils.cp_r(source.to_s, destination.to_s)
      end

      def execute_directive(line, content)
        command, *options = Shellwords.split(content)
        case command
        when "disable-logging"
          @context.logging = false
        when "enable-logging"
          @context.logging = true
        when "suggest-create-dataset"
          execute_directive_suggest_create_dataset(line, content, options)
        when "include"
          execute_directive_include(line, content, options)
        when "copy-path"
          execute_directive_copy_path(line, content, options)
        else
          log_input(line)
          log_error("#|e| unknown directive: <#{command}>")
        end
      end

      def execute_suggest_create_dataset(dataset_name)
        command_line = [@context.groonga_suggest_create_dataset,
                        @context.db_path.to_s,
                        dataset_name]
        packed_command_line = command_line.join(" ")
        log_input("#{packed_command_line}\n")
        begin
          IO.popen(command_line, "r:ascii-8bit") do |io|
            log_output(io.read)
          end
        rescue SystemCallError
          raise Error.new("failed to run groonga-suggest-create-dataset: " +
                            "<#{packed_command_line}>: #{$!}")
        end
      end

      def execute_script(script_path)
        executor = create_sub_executor(@context)
        executor.execute(resolve_path(script_path))
      end

      def execute_command_line(command_line)
        extract_command_info(command_line)
        log_input(command_line)
        if multiline_load_command?
          @loading = true
          @pending_load_command = command_line.dup
        else
          execute_command(command_line)
        end
      end

      def extract_command_info(command_line)
        @current_command, *@current_arguments = Shellwords.split(command_line)
        if @current_command == "dump"
          @output_type = "groonga-command"
        else
          @output_type = @context.output_type
          @current_arguments.each_with_index do |word, i|
            if /\A--output_type(?:=(.+))?\z/ =~ word
              @output_type = $1 || words[i + 1]
              break
            end
          end
        end
      end

      def have_output_type_argument?
        @current_arguments.any? do |argument|
          /\A--output_type(?:=.+)?\z/ =~ argument
        end
      end

      def multiline_load_command?
        @current_command == "load" and
          not @current_arguments.include?("--values")
      end

      def execute_command(command)
        log_output(send_command(command))
        log_error(read_error_log)
      end

      def read_error_log
        log = read_all_readable_content(context.log, :first_timeout => 0)
        normalized_error_log = ""
        log.each_line do |line|
          timestamp, log_level, message = line.split(/\|\s*/, 3)
          _ = timestamp # suppress warning
          next unless error_log_level?(log_level)
          next if backtrace_log_message?(message)
          normalized_error_log << "\#|#{log_level}| #{message}"
        end
        normalized_error_log.chomp
      end

      def read_all_readable_content(output, options={})
        content = ""
        first_timeout = options[:first_timeout] || 1
        timeout = first_timeout
        while IO.select([output], [], [], timeout)
          break if output.eof?
          request_bytes = 1024
          read_content = output.readpartial(request_bytes)
          content << read_content
          timeout = 0 if read_content.bytesize < request_bytes
        end
        content
      end

      def error_log_level?(log_level)
        ["E", "A", "C", "e"].include?(log_level)
      end

      def backtrace_log_message?(message)
        message.start_with?("/")
      end

      def log(tag, content, options={})
        return unless @context.logging?
        log_force(tag, content, options)
      end

      def log_force(tag, content, options)
        return if content.empty?
        @context.result << [tag, content, options]
      end

      def log_input(content)
        log(:input, content)
      end

      def log_output(content)
        log(:output, content,
            :command => @current_command,
            :type => @output_type)
        @current_command = nil
        @output_type = nil
      end

      def log_error(content)
        log_force(:error, content, {})
      end
    end

    class StandardIOExecutor < Executor
      def initialize(input, output, context=nil)
        super(context)
        @input = input
        @output = output
      end

      def send_command(command_line)
        unless have_output_type_argument?
          command_line = command_line.sub(/$/, " --output_type #{@output_type}")
        end
        begin
          @input.print(command_line)
          @input.flush
        rescue SystemCallError
          message = "failed to write to groonga: <#{command_line}>: #{$!}"
          raise Error.new(message)
        end
        read_output
      end

      def ensure_groonga_ready
        @input.print("status\n")
        @input.flush
        @output.gets
      end

      def create_sub_executor(context)
        self.class.new(@input, @output, context)
      end

      private
      def read_output
        read_all_readable_content(@output)
      end
    end

    class HTTPExecutor < Executor
      def initialize(host, port, context=nil)
        super(context)
        @host = host
        @port = port
      end

      def send_command(command_line)
        converter = CommandFormatConverter.new(command_line)
        url = "http://#{@host}:#{@port}#{converter.to_url}"
        begin
          open(url) do |response|
            "#{response.read}\n"
          end
        rescue OpenURI::HTTPError
          message = "Failed to get response from groonga: #{$!}: <#{url}>"
          raise Error.new(message)
        end
      end

      def ensure_groonga_ready
        n_retried = 0
        begin
          send_command("status")
        rescue SystemCallError
          n_retried += 1
          sleep(0.1)
          retry if n_retried < 10
          raise
        end
      end

      def create_sub_executor(context)
        self.class.new(@host, @port, context)
      end
    end

    class CommandFormatConverter
      def initialize(gqtp_command)
        @gqtp_command = gqtp_command
      end

      def to_url
        command = nil
        arguments = nil
        load_values = ""
        @gqtp_command.each_line.with_index do |line, i|
          if i.zero?
            command, *arguments = Shellwords.split(line)
          else
            load_values << line
          end
        end
        arguments.concat(["--values", load_values]) unless load_values.empty?

        named_arguments = convert_to_named_arguments(command, arguments)
        build_url(command, named_arguments)
      end

      private
      def convert_to_named_arguments(command, arguments)
        named_arguments = {}

        last_argument_name = nil
        n_non_named_arguments = 0
        arguments.each do |argument|
          if /\A--/ =~ argument
            last_argument_name = $POSTMATCH
            next
          end

          if last_argument_name.nil?
            argument_name = arguments_name(command)[n_non_named_arguments]
            n_non_named_arguments += 1
          else
            argument_name = last_argument_name
            last_argument_name = nil
          end

          named_arguments[argument_name] = argument
        end

        named_arguments
      end

      def arguments_name(command)
        case command
        when "table_create"
          ["name", "flags", "key_type", "value_type", "default_tokenizer"]
        when "column_create"
          ["table", "name", "flags", "type", "source"]
        when "load"
          ["values", "table", "columns", "ifexists", "input_type"]
        when "select"
          ["table"]
        when "suggest"
          [
            "types", "table", "column", "query", "sortby",
            "output_columns", "offset", "limit", "frequency_threshold",
            "conditional_probability_threshold", "prefix_search"
          ]
        when "truncate"
          ["table"]
        when "get"
          ["table", "key", "output_columns", "id"]
        else
          nil
        end
      end

      def build_url(command, named_arguments)
        url = "/d/#{command}"
        query_parameters = []
        named_arguments.each do |name, argument|
          query_parameters << "#{CGI.escape(name)}=#{CGI.escape(argument)}"
        end
        unless query_parameters.empty?
          url << "?"
          url << query_parameters.join("&")
        end
        url
      end
    end

    class BaseReporter
      def initialize(tester)
        @tester = tester
        @term_width = guess_term_width
        @output = @tester.output
        @mutex = Mutex.new
        reset_current_column
      end

      private
      def synchronize
        @mutex.synchronize do
          yield
        end
      end

      def report_summary(result)
        puts(statistics_header)
        puts(colorize(statistics(result), result))
        pass_ratio = result.pass_ratio
        elapsed_time = result.elapsed_time
        summary = "%.4g%% passed in %.4fs." % [pass_ratio, elapsed_time]
        puts(colorize(summary, result))
      end

      def statistics_header
        items = [
          "tests/sec",
          "tests",
          "passes",
          "failures",
          "leaked",
          "!checked",
        ]
        "  " + ((["%-9s"] * items.size).join(" | ") % items) + " |"
      end

      def statistics(result)
        items = [
          "%9.2f" % throughput(result),
          "%9d" % result.n_tests,
          "%9d" % result.n_passed_tests,
          "%9d" % result.n_failed_tests,
          "%9d" % result.n_leaked_tests,
          "%9d" % result.n_not_checked_tests,
        ]
        "  " + items.join(" | ") + " |"
      end

      def throughput(result)
        if result.elapsed_time.zero?
          tests_per_second = 0
        else
          tests_per_second = result.n_tests / result.elapsed_time
        end
        tests_per_second
      end

      def report_failure(result)
        report_marker(result)
        report_diff(result.expected, result.actual)
        report_marker(result)
      end

      def report_actual(result)
        report_marker(result)
        puts(result.actual)
        report_marker(result)
      end

      def report_marker(result)
        puts(colorize("=" * @term_width, result))
      end

      def report_diff(expected, actual)
        create_temporary_file("expected", expected) do |expected_file|
          create_temporary_file("actual", actual) do |actual_file|
            diff_options = @tester.diff_options.dup
            diff_options.concat(["--label", "(expected)", expected_file.path,
                                 "--label", "(actual)", actual_file.path])
            system(@tester.diff, *diff_options)
          end
        end
      end

      def report_test(worker, result)
        report_marker(result)
        print("[#{worker.id}] ") if @tester.n_workers > 1
        puts(worker.suite_name)
        print("  #{worker.test_name}")
        report_test_result(result, worker.status)
      end

      def report_test_result(result, label)
        message = test_result_message(result, label)
        message_width = string_width(message)
        rest_width = @term_width - @current_column
        if rest_width > message_width
          print(" " * (rest_width - message_width))
        end
        puts(message)
      end

      def test_result_message(result, label)
        elapsed_time = result.elapsed_time
        formatted_elapsed_time = "%.4fs" % elapsed_time
        formatted_elapsed_time = colorize(formatted_elapsed_time,
                                          elapsed_time_status(elapsed_time))
        " #{formatted_elapsed_time} [#{colorize(label, result)}]"
      end

      LONG_ELAPSED_TIME = 1.0
      def long_elapsed_time?(elapsed_time)
        elapsed_time >= LONG_ELAPSED_TIME
      end

      def elapsed_time_status(elapsed_time)
        if long_elapsed_time?(elapsed_time)
          elapsed_time_status = :failure
        else
          elapsed_time_status = :not_checked
        end
      end

      def justify(message, width)
        return " " * width if message.nil?
        return message.ljust(width) if message.bytesize <= width
        half_width = width / 2.0
        elision_mark = "..."
        left = message[0, half_width.ceil - elision_mark.size]
        right = message[(message.size - half_width.floor)..-1]
        "#{left}#{elision_mark}#{right}"
      end

      def print(message)
        @current_column += string_width(message.to_s)
        @output.print(message)
      end

      def puts(*messages)
        reset_current_column
        @output.puts(*messages)
      end

      def reset_current_column
        @current_column = 0
      end

      def create_temporary_file(key, content)
        file = Tempfile.new("groonga-test-#{key}")
        file.print(content)
        file.close
        yield(file)
      end

      def guess_term_width
        Integer(guess_term_width_from_env || guess_term_width_from_stty || 79)
      rescue ArgumentError
        0
      end

      def guess_term_width_from_env
        ENV["COLUMNS"] || ENV["TERM_WIDTH"]
      end

      def guess_term_width_from_stty
        case `stty -a`
        when /(\d+) columns/
          $1
        when /columns (\d+)/
          $1
        else
          nil
        end
      rescue SystemCallError
        nil
      end

      def string_width(string)
        string.gsub(/\e\[[0-9;]+m/, "").size
      end

      def result_status(result)
        if result.respond_to?(:status)
          result.status
        else
          if result.n_failed_tests > 0
            :failure
          elsif result.n_leaked_tests > 0
            :leaked
          elsif result.n_not_checked_tests > 0
            :not_checked
          else
            :success
          end
        end
      end

      def colorize(message, result_or_status)
        return message unless @tester.use_color?
        if result_or_status.is_a?(Symbol)
          status = result_or_status
        else
          status = result_status(result_or_status)
        end
        case status
        when :success
          "%s%s%s" % [success_color, message, reset_color]
        when :failure
          "%s%s%s" % [failure_color, message, reset_color]
        when :leaked
          "%s%s%s" % [leaked_color, message, reset_color]
        when :not_checked
          "%s%s%s" % [not_checked_color, message, reset_color]
        else
          message
        end
      end

      def success_color
        escape_sequence({
                          :color => :green,
                          :color_256 => [0, 3, 0],
                          :background => true,
                        },
                        {
                          :color => :white,
                          :color_256 => [5, 5, 5],
                          :bold => true,
                        })
      end

      def failure_color
        escape_sequence({
                          :color => :red,
                          :color_256 => [3, 0, 0],
                          :background => true,
                        },
                        {
                          :color => :white,
                          :color_256 => [5, 5, 5],
                          :bold => true,
                        })
      end

      def leaked_color
        escape_sequence({
                          :color => :magenta,
                          :color_256 => [3, 0, 3],
                          :background => true,
                        },
                        {
                          :color => :white,
                          :color_256 => [5, 5, 5],
                          :bold => true,
                        })
      end

      def not_checked_color
        escape_sequence({
                          :color => :cyan,
                          :color_256 => [0, 1, 1],
                          :background => true,
                        },
                        {
                          :color => :white,
                          :color_256 => [5, 5, 5],
                          :bold => true,
                        })
      end

      def reset_color
        escape_sequence(:reset)
      end

      COLOR_NAMES = [
        :black, :red, :green, :yellow,
        :blue, :magenta, :cyan, :white,
      ]
      def escape_sequence(*commands)
        sequence = []
        commands.each do |command|
          case command
          when :reset
            sequence << "0"
          when :bold
            sequence << "1"
          when :italic
            sequence << "3"
          when :underline
            sequence << "4"
          when Hash
            foreground_p = !command[:background]
            if available_colors == 256
              sequence << (foreground_p ? "38" : "48")
              sequence << "5"
              sequence << pack_256_color(*command[:color_256])
            else
              color_parameter = foreground_p ? 3 : 4
              color_parameter += 6 if command[:intensity]
              color = COLOR_NAMES.index(command[:color])
              sequence << "#{color_parameter}#{color}"
            end
          end
        end
        "\e[#{sequence.join(';')}m"
      end

      def pack_256_color(red, green, blue)
        red * 36 + green * 6 + blue + 16
      end

      def available_colors
        case ENV["COLORTERM"]
        when "gnome-terminal"
          256
        else
          case ENV["TERM"]
          when /-256color\z/
            256
          else
            8
          end
        end
      end
    end

    class MarkReporter < BaseReporter
      def initialize(tester)
        super
      end

      def start(result)
      end

      def start_worker(worker)
      end

      def start_suite(worker)
      end

      def start_test(worker)
      end

      def pass_test(worker, result)
        synchronize do
          report_test_result_mark(".", result)
        end
      end

      def fail_test(worker, result)
        synchronize do
          report_test_result_mark("F", result)
          puts
          report_test(worker, result)
          report_failure(result)
        end
      end

      def leaked_test(worker, result)
        synchronize do
          report_test_result_mark("L(#{result.n_leaked_objects})", result)
        end
      end

      def not_checked_test(worker, result)
        synchronize do
          report_test_result_mark("N", result)
          puts
          report_test(worker, result)
          report_actual(result)
        end
      end

      def finish_test(worker, result)
      end

      def finish_suite(worker)
      end

      def finish_worker(worker_id)
      end

      def finish(result)
        puts
        puts
        report_summary(result)
      end

      private
      def report_test_result_mark(mark, result)
        if @term_width < @current_column + mark.bytesize
          puts
        end
        print(colorize(mark, result))
        if @term_width <= @current_column
          puts
        else
          @output.flush
        end
      end
    end

    class StreamReporter < BaseReporter
      def initialize(tester)
        super
      end

      def start(result)
      end

      def start_worker(worker)
      end

      def start_suite(worker)
        if worker.suite_name.bytesize <= @term_width
          puts(worker.suite_name)
        else
          puts(justify(worker.suite_name, @term_width))
        end
        @output.flush
      end

      def start_test(worker)
        print("  #{worker.test_name}")
        @output.flush
      end

      def pass_test(worker, result)
        report_test_result(result, worker.status)
      end

      def fail_test(worker, result)
        report_test_result(result, worker.status)
        report_failure(result)
      end

      def leaked_test(worker, result)
        report_test_result(result, worker.status)
      end

      def not_checked_test(worker, result)
        report_test_result(result, worker.status)
        report_actual(result)
      end

      def finish_test(worker, result)
      end

      def finish_suite(worker)
      end

      def finish_worker(worker_id)
      end

      def finish(result)
        puts
        report_summary(result)
      end
    end

    class InplaceReporter < BaseReporter
      def initialize(tester)
        super
        @last_redraw_time = Time.now
        @minimum_redraw_interval = 0.1
      end

      def start(result)
        @test_suites_result = result
      end

      def start_worker(worker)
      end

      def start_suite(worker)
        redraw
      end

      def start_test(worker)
        redraw
      end

      def pass_test(worker, result)
        redraw
      end

      def fail_test(worker, result)
        redraw do
          report_test(worker, result)
          report_failure(result)
        end
      end

      def leaked_test(worker, result)
        redraw do
          report_test(worker, result)
          report_marker(result)
        end
      end

      def not_checked_test(worker, result)
        redraw do
          report_test(worker, result)
          report_actual(result)
        end
      end

      def finish_test(worker, result)
        redraw
      end

      def finish_suite(worker)
        redraw
      end

      def finish_worker(worker)
        redraw
      end

      def finish(result)
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
