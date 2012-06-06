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

        parser.on("--groonga-suggest-create-dataset=COMMAND",
                  "Use COMMAND as groonga_suggest_create_dataset command",
                  "(#{tester.groonga_suggest_create_dataset})") do |command|
          tester.groonga_suggest_create_dataset = command
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

    attr_accessor :groonga, :groonga_suggest_create_dataset
    attr_accessor :base_directory, :diff, :diff_options
    attr_writer :keep_database
    def initialize
      @groonga = "groonga"
      @groonga_suggest_create_dataset = "groonga-suggest-create-dataset"
      @base_directory = "."
      detect_suitable_diff
    end

    def run(*targets)
      succeeded = true
      return succeeded if targets.empty?

      reporter = Reporter.new(self)
      reporter.start
      catch do |tag|
        targets.each do |target|
          target_path = Pathname(target)
          next unless target_path.exist?
          if target_path.directory?
            unless run_tests_in_directory(target_path, reporter, tag)
              succeeded = false
            end
          else
            succeeded = false unless run_test(target_path, reporter, tag)
          end
        end
      end
      reporter.finish
      succeeded
    end

    def keep_database?
      @keep_database
    end

    private
    def collect_test_files(test_directory)
      test_files = Pathname.glob(test_directory + "**" + "*.test")
      grouped_test_files = test_files.group_by do |test_file|
        test_file.dirname.relative_path_from(test_directory)
      end
      grouped_test_files.sort_by do |directory, test_files|
        directory.to_s
      end
    end

    def run_tests_in_directory(test_directory, reporter, tag)
      succeeded = true
      collect_test_files(test_directory).each do |directory, test_files|
        suite_name = directory.to_s
        reporter.start_suite(suite_name)
        test_files.sort.each do |test_file|
          succeeded = false unless run_test(test_file, reporter, tag)
        end
        reporter.finish_suite(suite_name)
      end
      succeeded
    end

    def run_test(test_script_path, reporter, tag)
      runner = Runner.new(self, test_script_path)
      succeeded = runner.run(reporter)
      throw(tag) if runner.interrupted?
      succeeded
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

    def command_exist?(name)
      ENV["PATH"].split(File::PATH_SEPARATOR).each do |path|
        absolute_path = File.join(path, name)
        return true if File.executable?(absolute_path)
      end
      false
    end

    class Runner
      MAX_N_COLUMNS = 79

      def initialize(tester, test_script_path)
        @tester = tester
        @test_script_path = test_script_path
        @max_n_columns = MAX_N_COLUMNS
        @interrupted = false
      end

      def run(reporter)
        succeeded = true

        test_name = @test_script_path.basename.to_s
        reporter.start_test(test_name)
        actual_result = run_groonga_script
        actual_result = normalize_result(actual_result)
        expected_result = read_expected_result
        if expected_result
          if actual_result == expected_result
            reporter.pass_test
            remove_reject_file
          else
            reporter.fail_test(expected_result, actual_result)
            output_reject_file(actual_result)
            succeeded = false
          end
        else
          reporter.no_check_test(actual_result)
          output_actual_file(actual_result)
        end
        reporter.finish_test(test_name)

        succeeded
      end

      def interrupted?
        @interrupted
      end

      private
      def run_groonga_script
        create_temporary_directory do |directory_path|
          db_path = File.join(directory_path, "db")
          run_groonga(db_path) do |input, output|
            context = Executor::Context.new
            begin
              context.db_path = db_path
              context.base_directory = @tester.base_directory
              context.groonga_suggest_create_dataset =
                @tester.groonga_suggest_create_dataset
              executer = Executor.new(input, output, context)
              executer.execute(@test_script_path)
            rescue Interrupt
              @interrupted = true
            end
            context.result
          end
        end
      end

      def create_temporary_directory
        path = "tmp"
        FileUtils.rm_rf(path)
        FileUtils.mkdir_p(path)
        begin
          yield(path)
        ensure
          if @tester.keep_database? and File.exist?(path)
            FileUtils.rm_rf(keep_database_path)
            FileUtils.mv(path, keep_database_path)
          else
            FileUtils.rm_rf(path)
          end
        end
      end

      def keep_database_path
        @test_script_path.to_s.gsub(/\//, ".")
      end

      def run_groonga(db_path)
        read = 0
        write = 1
        input_pipe = IO.pipe
        output_pipe = IO.pipe

        input_fd = input_pipe[read].to_i
        output_fd = output_pipe[write].to_i
        command_line = [
          @tester.groonga,
          "--input-fd", input_fd.to_s,
          "--output-fd", output_fd.to_s,
          "-n", db_path,
        ]
        env = {}
        options = {
          input_fd => input_fd,
          output_fd => output_fd
        }
        pid = Process.spawn(env, *command_line, options)
        begin
          groonga_input = input_pipe[write]
          groonga_output = output_pipe[read]
          ensure_groonga_ready(groonga_input, groonga_output)
          yield(groonga_input, groonga_output)
        ensure
          (input_pipe + output_pipe).each do |io|
            io.close unless io.closed?
          end
          Process.waitpid(pid)
        end
      end

      def ensure_groonga_ready(input, output)
        input.print("status\n")
        input.flush
        output.gets
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
              status, *values = JSON.parse(content)
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

      def have_extension?
        not @test_script_path.extname.empty?
      end

      def related_file_path(extension)
        path = Pathname(@test_script_path.to_s.gsub(/\.[^.]+\z/, ".#{extension}"))
        return nil if @test_script_path == path
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
        FileUtils.rm_rf(reject_path.to_s)
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
        attr_accessor :base_directory, :db_path, :groonga_suggest_create_dataset
        attr_accessor :result
        def initialize
          @logging = true
          @base_directory = "."
          @db_path = "db"
          @groonga_suggest_create_dataset = "groonga-suggest-create-dataset"
          @n_nested = 0
          @result = []
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
      def initialize(input, output, context=nil)
        @input = input
        @output = output
        @loading = false
        @pending_command = ""
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
        @input.print(line)
        @input.flush
        if /\]$/ =~ line
          current_result = read_output
          unless current_result.empty?
            @loading = false
            log_output(current_result)
          end
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
          execute_command(line)
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
        executer = self.class.new(@input, @output, @context)
        script_path = Pathname(path)
        if script_path.relative?
          script_path = Pathname(@context.base_directory) + script_path
        end
        executer.execute(script_path)
      end

      def execute_command(line)
        extract_command_info(line)
        @loading = true if @current_command == "load"
        begin
          @input.print(line)
          @input.flush
        rescue SystemCallError
          raise Error.new("failed to write to groonga: <#{line}>: #{$!}")
        end
        log_input(line)
        unless @loading
          log_output(read_output)
        end
      end

      def extract_command_info(line)
        words = Shellwords.split(line)
        @current_command = words.shift
        if @current_command == "dump"
          @output_format = "groonga-command"
        else
          @output_format = "json"
          words.each_with_index do |word, i|
            if /\A--output_format(?:=(.+))?\z/ =~ word
              @output_format = $1 || words[i + 1]
              break
            end
          end
        end
      end

      def read_output
        output = ""
        first_timeout = 1
        timeout = first_timeout
        while IO.select([@output], [], [], timeout)
          break if @output.eof?
          output << @output.readpartial(65535)
          timeout = 0
        end
        output
      end

      def log(tag, content, options={})
        return unless @context.logging?
        return if content.empty?
        log_force(tag, content, options)
      end

      def log_force(tag, content, options)
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

    class CommandTranslator
      def translate_url(line)
        line = line.chomp
        return "" if line.empty?

        line = line.gsub(/"/, "\\\\\"")
        json = line[/\[.+\]/]

        unless json.nil?
          line[/\[.+\]/] = "--values #{json.gsub(/\s/, "")}"
        end

        now_command, *arguments = Shellwords.split(line)

        translated_values = translate_arguments(now_command, arguments)
        url = build_url(now_command, translated_values)
        url
      end

      private
      def translate_arguments(now_command, arguments)
        return [] if arguments.empty?
        translated_values = {}
        last_argument = ""

        arguments_count = 0
        last_command = ""
        arguments.each do |argument|
          next if argument.empty?
          if argument =~ /\A--/
            last_command = argument.sub(/\A--/, "")
            next
          end

          if last_command.empty?
            query_parameter =
              arguments_name(now_command)[arguments_count]
          else
            query_parameter = last_command
          end

          value = argument.gsub(/\s/, "")
          translated_values =
            translated_values.merge(query_parameter => value)
          arguments_count += 1
          last_command = ""
        end
        translated_values
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

      def build_url(command, arguments)
        url = "/d/#{command}"
        query = Rack::Utils.build_query(arguments)
        url << "?#{query}" unless query.empty?
        url
      end
    end

    class Reporter
      def initialize(tester)
        @tester = tester
        @term_width = guess_term_width
        @current_column = 0
        @output = STDOUT
        @n_tests = 0
        @n_passed_tests = 0
        @n_not_checked_tests = 0
        @failed_tests = []
      end

      def start
      end

      def start_suite(suite_name)
        puts(suite_name)
        @output.flush
      end

      def start_test(test_name)
        @test_name = test_name
        print("  #{@test_name}")
        @output.flush
      end

      def pass_test
        report_test_result("pass")
        @n_passed_tests += 1
      end

      def fail_test(expected, actual)
        report_test_result("fail")
        puts("=" * @term_width)
        report_diff(expected, actual)
        puts("=" * @term_width)
        @failed_tests << @test_name
      end

      def no_check_test(result)
        report_test_result("not checked")
        puts(result)
        @n_not_checked_tests += 1
      end

      def finish_test(test_name)
        @n_tests += 1
      end

      def finish_suite(suite_name)
      end

      def finish
        puts
        puts("#{@n_tests} tests, " +
               "#{@n_passed_tests} passes, " +
               "#{@failed_tests.size} failures, " +
               "#{@n_not_checked_tests} not checked tests.")
        if @n_tests.zero?
          pass_ratio = 0
        else
          pass_ratio = (@n_passed_tests / @n_tests.to_f) * 100
        end
        puts("%.4g%% passed." % pass_ratio)
      end

      private
      def print(message)
        @current_column += message.to_s.size
        @output.print(message)
      end

      def puts(*messages)
        @current_column = 0
        @output.puts(*messages)
      end

      def report_test_result(label)
        message = " [#{label}]"
        message = message.rjust(@term_width - @current_column) if @term_width > 0
        puts(message)
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

      def guess_term_width
        Integer(ENV["COLUMNS"] || ENV["TERM_WIDTH"] || 79)
      rescue ArgumentError
        0
      end
    end
  end
end
