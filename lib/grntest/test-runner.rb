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

require "pathname"
require "fileutils"
require "tempfile"

require "json"

require "grntest/error"
require "grntest/log-parser"
require "grntest/executors"
require "grntest/base-result"

module Grntest
  class TestResult < BaseResult
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
        context = ExecutionContext.new
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
          executor = Executors::StandardIOExecutor.new(groonga_input,
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
        gdb_command_path.open("w") do |gdb_command|
          gdb_command.puts(<<-COMMANDS)
break main
run
call chdir("#{context.temporary_directory_path}")
          COMMANDS
        end
        command_line << "--command=#{gdb_command_path}"
        command_line << "--quiet"
        command_line << "--args"
      elsif @tester.valgrind
        if libtool_wrapper?(command)
          command_line << find_libtool(command)
          command_line << "--mode=execute"
        end
        command_line << @tester.valgrind
        command_line << "--leak-check=full"
        command_line << "--show-reachable=yes"
        command_line << "--track-origins=yes"
        valgrind_suppressions_file_path =
          context.temporary_directory_path + "groonga.supp"
        valgrind_suppressions_file_path.open("w") do |suppressions|
          suppressions.puts(<<-SUPPRESSIONS)
{
  dlopen
  Memcheck:Leak
  match-leak-kinds: reachable
  ...
  fun:dlopen*
  ...
}
{
  _dl_catch_error
  Memcheck:Leak
  match-leak-kinds: reachable
  ...
  fun:_dl_catch_error
}
          SUPPRESSIONS
        end
        command_line << "--suppressions=#{valgrind_suppressions_file_path}"
        if @tester.valgrind_gen_suppressions?
          command_line << "--gen-suppressions=all"
        end
        command_line << "--verbose"
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
      shutdown_wait_timeout = 5
      begin
        pid = Process.spawn(env, *command_line, spawn_options)
        begin
          executor = Executors::HTTPExecutor.new(host, port, context)
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
          executor.shutdown
          if wait_groonga_http_shutdown(pid_file_path, shutdown_wait_timeout)
            pid = nil if wait_pid(pid, shutdown_wait_timeout)
          end
        end
      ensure
        return if pid.nil?
        Process.kill(:TERM, pid)
        wait_groonga_http_shutdown(pid_file_path, shutdown_wait_timeout)
        ensure_process_finished(pid)
      end
    end

    def ensure_process_finished(pid)
      return if pid.nil?

      n_retries = 0
      loop do
        finished_pid = Process.waitpid(pid, Process::WNOHANG)
        break if finished_pid
        n_retries += 1
        break if n_retries > 100
        Process.kill(:TERM, pid)
        sleep(0.1)
      end
    end

    def wait_pid(pid, timeout)
      total_sleep_time = 0
      sleep_time = 0.1
      loop do
        return true if Process.waitpid(pid, Process::WNOHANG)
        sleep(sleep_time)
        total_sleep_time += sleep_time
        return false if total_sleep_time > timeout
      end
    end

    def wait_groonga_http_shutdown(pid_file_path, timeout)
      return false unless pid_file_path.exist?

      total_sleep_time = 0
      sleep_time = 0.1
      while pid_file_path.exist?
        sleep(sleep_time)
        total_sleep_time += sleep_time
        break if total_sleep_time > timeout
      end
      true
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
        config_file.puts(<<-GLOBAL)
daemon off;
master_process off;
worker_processes 1;
working_directory #{context.temporary_directory_path};
error_log groonga-httpd-error.log;
pid #{pid_file_path};
events {
     worker_connections 1024;
}
        GLOBAL

        ENV.each do |key, value|
          next unless key.start_with?("GRN_")
          config_file.puts(<<-ENV)
env #{key};
          ENV
        end
        config_file.puts(<<-ENV)
env LD_LIBRARY_PATH;
env DYLD_LIBRARY_PATH;
        ENV

        config_file.puts(<<-HTTP)
http {
     server {
             access_log groonga-httpd-access.log;
             listen #{port};
             server_name #{host};
             location /d/ {
                     groonga_database #{context.relative_db_path};
                     groonga_log_path #{context.log_path};
                     groonga on;
            }
     }
}
        HTTP
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
      options = {
        output_fd.to_i => output_fd.to_i
      }
      system(*create_database_command, options)
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
          normalized_result << normalize_error(content)
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
        normalized_values = normalize_values(values)
        normalized_output_content = [normalized_status, *normalized_values]
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
        message = normalize_path_in_error_message(message)
        [[return_code, 0.0, 0.0], message]
      end
    end

    def normalize_values(values)
      values.collect do |value|
        if value.is_a?(Hash) and value["exception"]
          exception = Marshal.load(Marshal.dump(value["exception"]))
          message = exception["message"]
          exception["message"] = normalize_path_in_error_message(message)
          value.merge("exception" => exception)
        else
          value
        end
      end
    end

    def normalize_error(content)
      content = normalize_path_in_error_message(content)
      normalize_raw_content(content)
    end

    def normalize_path_in_error_message(content)
      case content
      when /\A(.*'fopen: failed to open mruby script file: )<(.+?)>'(.*)\z/
        pre = $1
        path = $2
        post = $3
        normalized_path = File.basename(path)
        post = post.gsub(/\[\d+\]\z/, "[?]")
        post = "" unless /[\)\]]\z/ =~ post
        "#{pre}<#{normalized_path}>'#{post}"
      else
        content
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
      parser = LogParser.new
      parser.parse(context.log) do |entry|
        next unless /^grn_fin \((\d+)\)$/ =~ entry.message
        n_leaked_objects = $1.to_i
        next if n_leaked_objects.zero?
        context.result << [:n_leaked_objects, n_leaked_objects, {}]
      end
    end
  end
end
