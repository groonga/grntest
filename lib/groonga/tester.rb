#!/usr/bin/env ruby
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
require "json"
require "shellwords"
require "open-uri"
require "cgi/util"

module Groonga
  class Tester
    VERSION = "1.0.0"

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

        available_protocols = [:gqtp, :http]
        available_protocol_labels = available_protocols.join(", ")
        parser.on("--protocol=PROTOCOL", available_protocols,
                  "Use PROTOCOL for communicating groonga",
                  "[#{available_protocol_labels}]",
                  "(#{tester.protocol})") do |protocol|
          tester.protocol = protocol
        end

        available_testees = ["groonga", "groonga-httpd"]
        available_testee_labels = available_testees.join(", ")
        parser.on("--testee=TESTEE", available_testees,
                  "Test against TESTEE",
                  "[#{available_testee_labels}]",
                  "(#{tester.testee})") do |testee|
          tester.testee = testee
          if tester.testee == "groonga-httpd"
            tester.protocol = :http
          end
        end

        parser.on("--base-directory=DIRECTORY",
                  "Use DIRECTORY as a base directory of relative path",
                  "(#{tester.base_directory})") do |directory|
          tester.base_directory = directory
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

        available_reporters = [:stream, :inplace]
        available_reporter_labels = available_reporters.join(", ")
        parser.on("--reporter=REPORTER", available_reporters,
                  "Report test result by REPORTER",
                  "[#{available_reporter_labels}]",
                  "(#{tester.reporter})") do |reporter|
          tester.reporter = reporter
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

        parser.on("--version",
                  "Show version and exit") do
          puts(GroongaTester::VERSION)
          throw(tag, true)
        end

        parser
      end
    end

    attr_accessor :groonga, :groonga_httpd, :groonga_suggest_create_dataset
    attr_accessor :protocol, :testee
    attr_accessor :base_directory, :diff, :diff_options, :reporter
    attr_accessor :n_workers
    attr_accessor :gdb, :default_gdb
    attr_writer :keep_database
    def initialize
      @groonga = "groonga"
      @groonga_httpd = "groonga-httpd"
      @groonga_suggest_create_dataset = "groonga-suggest-create-dataset"
      @protocol = :gqtp
      @testee = "groonga"
      @base_directory = "."
      @reporter = :stream
      @n_workers = 1
      detect_suitable_diff
      initialize_debuggers
    end

    def run(*targets)
      succeeded = true
      return succeeded if targets.empty?

      test_suites = load_tests(*targets)
      run_test_suites(test_suites)
    end

    def keep_database?
      @keep_database
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

    class Worker
      attr_reader :id, :tester, :test_suites_rusult, :reporter
      attr_reader :suite_name, :test_script_path, :status
      def initialize(id, tester, test_suites_result, reporter)
        @id = id
        @tester = tester
        @test_suites_result = test_suites_result
        @reporter = reporter
        @suite_name = nil
        @test_script_path = nil
        @interruptted = false
        @status = "not running"
      end

      def interrupt
        @interruptted = true
      end

      def interruptted?
        @interruptted
      end

      def test_name
        return nil if @test_script_path.nil?
        @test_script_path.basename(".*").to_s
      end

      def run(queue)
        succeeded = true

        @reporter.start_worker(self)
        catch do |tag|
          loop do
            suite_name, test_script_path = queue.pop
            break if test_script_path.nil?

            unless @suite_name == suite_name
              @reporter.finish_suite(self) if @suite_name
              @suite_name = suite_name
              @reporter.start_suite(self)
            end
            @test_script_path = test_script_path
            runner = TestRunner.new(@tester, self)
            succeeded = false unless runner.run

            break if interruptted?
          end
          @status = "finished"
          @reporter.finish_suite(@suite_name) if @suite_name
          @suite_name = nil
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
        @test_suites_result.test_passed
        @reporter.pass_test(self, result)
      end

      def fail_test(result)
        @status = "failed"
        @test_suites_result.test_failed(test_name)
        @reporter.fail_test(self, result)
      end

      def no_check_test(result)
        @status = "not checked"
        @test_suites_result.test_not_checked
        @reporter.no_check_test(self, result)
      end

      def finish_test(result)
        @test_suites_result.test_finished
        @reporter.finish_test(self, result)
        @test_script_path = nil
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

    class TestSuitesResult < Result
      attr_reader :n_tests, :n_passed_tests, :n_not_checked_tests
      attr_reader :failed_tests
      def initialize
        super
        @n_tests = 0
        @n_passed_tests = 0
        @n_not_checked_tests = 0
        @failed_tests = []
      end

      def n_failed_tests
        @failed_tests.size
      end

      def pass_ratio
        if @n_tests.zero?
          0
        else
          (@n_passed_tests / @n_tests.to_f) * 100
        end
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

      def test_not_checked
        @n_not_checked_tests += 1
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
          test_script_paths.each do |test_script_path|
            queue << [suite_name, test_script_path]
          end
        end
        @tester.n_workers.times do
          queue << nil
        end

        workers = []
        @tester.n_workers.times do |i|
          workers << Worker.new(i, @tester, @result, @reporter)
        end
        @reporter.start(workers.dup)

        succeeded = true
        worker_threads = []
        @tester.n_workers.times do |i|
          worker = workers[i]
          worker_threads << Thread.new do
            succeeded = worker.run(queue)
            workers.delete(worker)
            if worker.interruptted?
              workers.each do |other_worker|
                other_worker.interrupt
              end
            end
          end
        end
        worker_threads.each(&:join)

        succeeded
      end

      def create_reporter
        case @tester.reporter
        when :stream
          StreamReporter.new(@tester)
        when :inplace
          InplaceReporter.new(@tester)
        end
      end
    end

    class TestResult < Result
      attr_accessor :worker_id, :test_name
      attr_accessor :expected, :actual
      def initialize(worker)
        super()
        @worker_id = worker.id
        @test_name = worker.test_name
        @actual = nil
        @expected = nil
      end

      def status
        if @expected
          if @actual == @expected
            :pass
          else
            :fail
          end
        else
          :no_check
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
          result.actual = run_groonga_script
        end
        result.actual = normalize_result(result.actual)
        result.expected = read_expected_result
        case result.status
        when :pass
          @worker.pass_test(result)
          remove_reject_file
        when :fail
          @worker.fail_test(result)
          output_reject_file(result.actual)
          succeeded = false
        else
          @worker.no_check_test(result)
          output_actual_file(result.actual)
        end
        @worker.finish_test(result)

        succeeded
      end

      private
      def run_groonga_script
        create_temporary_directory do |directory_path|
          db_path = File.join(directory_path, "db")
          context = Executor::Context.new
          begin
            context.temporary_directory_path = directory_path
            context.db_path = db_path
            context.base_directory = @tester.base_directory
            context.groonga_suggest_create_dataset =
              @tester.groonga_suggest_create_dataset
            run_groonga(context) do |executor|
              executor.execute(test_script_path)
            end
          rescue Interrupt
            @worker.interrupted
          end
          context.result
        end
      end

      def create_temporary_directory
        path = "tmp/grntest"
        path << ".#{@worker.id}" if @tester.n_workers > 1
        FileUtils.rm_rf(path, :secure => true)
        FileUtils.mkdir_p(path)
        begin
          yield(path)
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
        case @tester.protocol
        when :gqtp
          run_groonga_gqtp(context, &block)
        when :http
          run_groonga_http(context, &block)
        end
      end

      def run_groonga_gqtp(context)
        pid = nil
        begin
          open_pipe do |input_read, input_write, output_read, output_write|
            groonga_input = input_write
            groonga_output = output_read

            input_fd = input_read.to_i
            output_fd = output_write.to_i
            command_line = groonga_command_line(context)
            command_line += [
              "--input-fd", input_fd.to_s,
              "--output-fd", output_fd.to_s,
              "-n", context.db_path,
            ]
            env = {}
            options = {
              input_fd => input_fd,
              output_fd => output_fd
            }
            pid = Process.spawn(env, *command_line, options)
            executor = GQTPExecutor.new(groonga_input, groonga_output, context)
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

      def groonga_command_line(context)
        command_line = []
        groonga = @tester.groonga
        if @tester.gdb
          if libtool_wrapper?(groonga)
            command_line << find_libtool(groonga)
            command_line << "--mode=execute"
          end
          command_line << @tester.gdb
          gdb_command_path = File.join(context.temporary_directory_path,
                                       "groonga.gdb")
          File.open(gdb_command_path, "w") do |gdb_command|
            gdb_command.puts(<<-EOC)
break main
run
EOC
          end
          command_line << "--command=#{gdb_command_path}"
          command_line << "--args"
        end
        command_line << groonga
        command_line << "--log-path=#{context.log_path}"
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
        port = 50041
        pid_file = Tempfile.new("groonga.pid")

        command_line = groonga_http_command(host, port, pid_file, context)
        system(*command_line)
        begin
          executor = HTTPExecutor.new(host, port, context)
          executor.ensure_groonga_ready
          yield(executor)
        ensure
          begin
            case @tester.testee
            when "groonga"
              executor.send_command("shutdown")
            when "groonga-httpd"
              command_line.concat(["-s", "quit"])
              system(*command_line)
            end
          rescue SystemCallError
          end

          wait_groonga_http_shutdown(pid_file)
        end
      end

      def wait_groonga_http_shutdown(pid_file)
        total_sleep_time = 0
        sleep_time = 0.1
        while File.exist?(pid_file.path)
          sleep(sleep_time)
          total_sleep_time += sleep_time
          break if total_sleep_time > 1.0
        end
      end

      def groonga_http_command(host, port, pid_file, context)
        case @tester.testee
        when "groonga"
          command_line = [
            @tester.groonga,
            "--pid-path", pid_file.path,
            "--bind-address", host,
            "--port", port.to_s,
            "--protocol", @tester.protocol.to_s,
            "--log-path", context.log_path,
            "-d",
            "-n", context.db_path,
          ]
        when "groonga-httpd"
          db_path = context.db_path
          config_file = create_config_file(host, port, db_path, pid_file)
          command_line = [
            @tester.groonga_httpd,
            "-c", config_file.path,
            "-p", File.join(File.dirname(db_path), "/"),
          ]
        end
        command_line
      end

      def create_config_file(host, port, db_path, pid_file)
        create_empty_database(db_path)
        config_file = Tempfile.new("test-httpd.conf")
        config_file.puts <<EOF
worker_processes 1;
pid #{pid_file.path};
events {
     worker_connections 1024;
}

http {
     server {
             error_log groonga-httpd-error.log;
             access_log groonga-httpd-access.log;
             listen #{port};
             server_name #{host};
             location /d/ {
                     groonga_database #{db_path};
                     groonga on;
            }
     }
}
EOF
        config_file.close
        config_file
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

      def normalize_result(result)
        normalized_result = ""
        result.each do |tag, content, options|
          case tag
          when :input
            normalized_result << content
          when :output
            case options[:format]
            when "json"
              begin
                status, *values = JSON.parse(content)
              rescue JSON::ParserError
                # extract failed reason from 1st json output.
                parsestr = content.split("\n")[0]
                status, *values = JSON.parse(parsestr)
              end
              normalized_status = normalize_status(status)
              normalized_output_content = [normalized_status, *values]
              normalized_output = JSON.generate(normalized_output_content)
              if normalized_output.bytesize > @max_n_columns
                normalized_output = JSON.pretty_generate(normalized_output_content)
              end
              normalized_output.force_encoding("ASCII-8BIT")
              normalized_result << "#{normalized_output}\n"
            else
              normalized_result << "#{content}\n".force_encoding("ASCII-8BIT")
            end
          when :error
            normalized_result << "#{content}\n".force_encoding("ASCII-8BIT")
          end
        end
        normalized_result
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
    end

    class Executor
      class Context
        attr_writer :logging
        attr_accessor :base_directory, :temporary_directory_path, :db_path
        attr_accessor :groonga_suggest_create_dataset
        attr_accessor :result
        def initialize
          @logging = true
          @base_directory = "."
          @temporary_directory_path = "tmp"
          @db_path = "db"
          @groonga_suggest_create_dataset = "groonga-suggest-create-dataset"
          @n_nested = 0
          @result = []
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
          File.join(@temporary_directory_path, "groonga.log")
        end

        def log
          @log ||= File.open(log_path, "a+")
        end
      end

      class Error < StandardError
      end

      class NotExist < Error
        attr_reader :path
        def initialize(path)
          @path = path
          super("<#{path}> doesn't exist.")
        end
      end

      attr_reader :context
      def initialize(context=nil)
        @loading = false
        @pending_command = ""
        @pending_load_command = nil
        @current_command_name = nil
        @output_format = nil
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
        when /\A\s*\z/
          # do nothing
        when /\A\s*\#/
          comment_content = $POSTMATCH
          execute_comment(comment_content)
        else
          execute_command_line(line)
        end
      end

      def execute_comment(content)
        command, *options = Shellwords.split(content)
        case command
        when "disable-logging"
          @context.logging = false
        when "enable-logging"
          @context.logging = true
        when "suggest-create-dataset"
          dataset_name = options.first
          return if dataset_name.nil?
          execute_suggest_create_dataset(dataset_name)
        when "include"
          path = options.first
          return if path.nil?
          execute_script(path)
        end
      end

      def execute_suggest_create_dataset(dataset_name)
        command_line = [@context.groonga_suggest_create_dataset,
                        @context.db_path,
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

      def execute_script(path)
        executor = create_sub_executor(@context)
        script_path = Pathname(path)
        if script_path.relative?
          script_path = Pathname(@context.base_directory) + script_path
        end
        executor.execute(script_path)
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
          @output_format = "groonga-command"
        else
          @output_format = "json"
          @current_arguments.each_with_index do |word, i|
            if /\A--output_format(?:=(.+))?\z/ =~ word
              @output_format = $1 || words[i + 1]
              break
            end
          end
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
          content << output.readpartial(65535)
          timeout = 0
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
            :format => @output_format)
        @current_command = nil
        @output_format = nil
      end

      def log_error(content)
        log_force(:error, content, {})
      end
    end

    class GQTPExecutor < Executor
      def initialize(input, output, context=nil)
        super(context)
        @input = input
        @output = output
      end

      def send_command(command_line)
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
        @output = STDOUT
        reset_current_column
      end

      private
      def print(message)
        @current_column += message.to_s.size
        @output.print(message)
        @output.flush
      end

      def puts(*messages)
        reset_current_column
        @output.puts(*messages)
      end

      def reset_current_column
        @current_column = 0
      end

      def guess_term_width
        Integer(ENV["COLUMNS"] || ENV["TERM_WIDTH"] || 79)
      rescue ArgumentError
        0
      end
    end

    class StreamReporter < BaseReporter
      def initialize(tester)
        super
      end

      def start(workers)
      end

      def start_worker(worker)
      end

      def start_suite(worker)
        puts(worker.suite_name)
        @output.flush
      end

      def start_test(worker)
        label = "  #{worker.test_name}"
        print(label)
        @output.flush
      end

      def pass_test(worker, result)
        report_test_result(result, worker.status)
        puts
      end

      def fail_test(worker, result)
        report_test_result(result, worker.status)
        puts
        puts("=" * @term_width)
        report_diff(result.expected, result.actual)
        puts("=" * @term_width)
      end

      def no_check_test(worker, result)
        report_test_result(result, worker.status)
        puts
        puts(result.actual)
      end

      def finish_test(worker, result)
      end

      def finish_suite(worker)
      end

      def finish_worker(worker_id)
      end

      def finish(result)
        puts
        puts("#{result.n_tests} tests, " +
               "#{result.n_passed_tests} passes, " +
               "#{result.n_failed_tests} failures, " +
               "#{result.n_not_checked_tests} not checked tests.")
        pass_ratio = result.pass_ratio
        elapsed_time = result.elapsed_time
        puts("%.4g%% passed in %.4fs." % [pass_ratio, elapsed_time])
      end

      private
      def report_test_result(result, label)
        message = " %10.4fs [%s]" % [result.elapsed_time, label]
        message = message.rjust(@term_width - @current_column) if @term_width > 0
        print(message)
      end

      def report_diff(expected, actual)
        create_temporary_file("expected", expected) do |expected_file|
          create_temporary_file("actual", actual) do |actual_file|
            diff_options = @tester.diff_options.dup
            diff_options.concat(["--label", "(actual)", actual_file.path,
                                 "--label", "(expected)", expected_file.path])
            system(@tester.diff, *diff_options)
          end
        end
      end

      def create_temporary_file(key, content)
        file = Tempfile.new("groonga-test-#{key}")
        file.print(content)
        file.close
        yield(file)
      end
    end

    class InplaceReporter < BaseReporter
      def initialize(tester)
        super
        @mutex = Mutex.new
        @workers = nil
      end

      def start(workers)
        @workers = workers
        n_workers.times do
          puts
          puts
        end
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
        redraw
      end

      def no_check_test(worker, result)
        redraw
      end

      def finish_test(worker, result)
        redraw
      end

      def finish_suite(worker)
        redraw
      end

      def finish_worker(worker_id)
        redraw
      end

      def finish(result)
        puts
        puts("#{result.n_tests} tests, " +
               "#{result.n_passed_tests} passes, " +
               "#{result.n_failed_tests} failures, " +
               "#{result.n_not_checked_tests} not checked tests.")
        pass_ratio = result.pass_ratio
        elapsed_time = result.elapsed_time
        puts("%.4g%% passed in %.4fs." % [pass_ratio, elapsed_time])
      end

      private
      def redraw
        @mutex.synchronize do
          up_n_lines(n_using_lines)
          @workers.each do |worker|
            clear_line
            puts("[#{worker.id}] (#{worker.status}) #{worker.suite_name}")
            clear_line
            puts("  #{worker.test_name}")
          end
        end
      end

      def up_n_lines(n)
        print("\e[1A" * n)
      end

      def clear_line
        print(" " * @term_width)
        print("\r")
      end

      def n_using_lines
        2 * n_workers
      end

      def n_workers
        @tester.n_workers
      end
    end
  end
end
