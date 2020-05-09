# Copyright (C) 2012-2020  Sutou Kouhei <kou@clear-code.com>
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
require "shellwords"

require "groonga-log"
require "groonga-query-log"
require "groonga/command/parser"

require "grntest/error"
require "grntest/execution-context"
require "grntest/response-parser"
require "grntest/template-evaluator"
require "grntest/variable-expander"

module Grntest
  module Executors
    class BaseExecutor
      module ReturnCode
        SUCCESS = 0
      end

      attr_reader :context
      def initialize(context)
        @loading = false
        @pending_command = ""
        @pending_load_command = nil
        @output_type = nil
        @long_read_timeout = default_long_read_timeout
        @context = context
        @custom_important_log_levels = []
        @ignore_log_patterns = {}
      end

      def execute(script_path)
        unless script_path.exist?
          raise NotExist.new(script_path)
        end

        @context.execute do
          script_path.open("r:ascii-8bit") do |script_file|
            parser = create_parser
            script_file.each_line do |line|
              begin
                parser << line
              rescue Error, Groonga::Command::Parser::Error
                line_info = "#{script_path}:#{script_file.lineno}:#{line.chomp}"
                log_error("#{line_info}: #{$!.message.b}")
                if $!.is_a?(Groonga::Command::Parser::Error)
                  @context.abort
                else
                  log_error("#{line_info}: #{$!.message.b}")
                  raise unless @context.top_level?
                end
              end
            end
          end
        end

        @context.result
      end

      def shutdown(pid)
        begin
          Timeout.timeout(@context.timeout) do
            send_command(command("shutdown"))
          end
        rescue
          return false
        end

        status = nil
        total_sleep_time = 0
        sleep_time = 0.05
        loop do
          _, status = Process.waitpid2(pid, Process::WNOHANG)
          break if status
          sleep(sleep_time)
          total_sleep_time += sleep_time
          return false if total_sleep_time > context.shutdown_wait_timeout
        end

        log_error(read_all_log) unless status.success?
        true
      end

      private
      def command(command_line)
        Groonga::Command::Parser.parse(command_line)
      end

      def create_parser
        parser = Groonga::Command::Parser.new
        parser.on_command do |command|
          execute_command(command)
        end
        parser.on_load_value do |command, value|
          command.values ||= []
          command.values << value
        end
        parser.on_load_complete do |command|
          if command.columns
            command[:columns] = command.columns.join(", ")
          end
          if command.values
            command[:values] = JSON.generate(command.values)
          end
          execute_command(command)
        end
        parser.on_comment do |comment|
          if /\A@/ =~ comment
            directive_content = $POSTMATCH
            execute_directive(parser, "\##{comment}", directive_content)
          end
        end
        parser
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

      def expand_variables(string)
        expander = VariableExpander.new(@context)
        expander.expand(string)
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
        source = resolve_path(Pathname(expand_variables(source)))
        destination = resolve_path(Pathname(expand_variables(destination)))
        FileUtils.cp_r(source.to_s, destination.to_s)
      end

      def timeout_value(key, line, input, default)
        new_value = nil

        invalid_value_p = false
        case input
        when "default"
          new_value = default
        when nil
          invalid_value_p = true
        else
          begin
            new_value = Float(input)
          rescue ArgumentError
            invalid_value_p = true
          end
        end

        if invalid_value_p
          log_input(line)
          message = "#{key} must be number or 'default': <#{input}>"
          log_error("#|e| [#{key}] #{message}")
          nil
        else
          new_value
        end
      end

      def execute_directive_timeout(line, content, options)
        timeout, = options
        new_value = timeout_value("timeout",
                                  line,
                                  timeout,
                                  @context.default_timeout)
        @context.timeout = new_value unless new_value.nil?
      end

      def execute_directive_read_timeout(line, content, options)
        timeout, = options
        new_value = timeout_value("read-timeout",
                                  line,
                                  timeout,
                                  @context.default_read_timeout)
        @context.read_timeout = new_value unless new_value.nil?
      end

      def execute_directive_long_read_timeout(line, content, options)
        timeout, = options
        new_value = timeout_value("long-read-timeout",
                                  line,
                                  timeout,
                                  default_long_read_timeout)
        @long_read_timeout = new_value unless new_value.nil?
      end

      def execute_directive_on_error(line, content, options)
        action, = options
        invalid_value_p = false
        valid_actions = ["default", "omit"]
        if valid_actions.include?(action)
          @context.on_error = action.to_sym
        else
          invalid_value_p = true
        end

        if invalid_value_p
          log_input(line)
          valid_actions_label = "[#{valid_actions.join(', ')}]"
          message = "on-error must be one of #{valid_actions_label}"
          log_error("#|e| [on-error] #{message}: <#{action}>")
        end
      end

      def execute_directive_omit(line, content, options)
        reason, = options
        omit(reason)
      end

      def omit(reason)
        @output_type = "raw"
        log_output("omit: #{reason}")
        @context.omit
      end

      def execute_directive_add_important_log_levels(line, content, options)
        log_levels = options.collect do |log_level|
          normalize_log_level(log_level)
        end
        @custom_important_log_levels |= log_levels
      end

      def execute_directive_remove_important_log_levels(line, content, options)
        log_levels = options.collect do |log_level|
          normalize_log_level(log_level)
        end
        @custom_important_log_levels -= log_levels
      end

      def normalize_log_level(level)
        case level
        when "info"
          level = "information"
        end
        level.to_sym
      end

      def execute_directive_sleep(line, content, options)
        time = options[0].to_f
        sleep(time) if time >= 0
      end

      def execute_directive_collect_query_log(line, content, options)
        @context.collect_query_log = (options[0] == "true")
      end

      def execute_directive_generate_series(parser, line, content, options)
        start, stop, table, template, = options
        evaluator = TemplateEvaluator.new(template)
        (Integer(start)..Integer(stop)).each_slice(1000) do |range|
          parser << "load --table #{table}\n"
          parser << "["
          first_record = true
          range.each do |i|
            record = ""
            if first_record
              first_record = false
            else
              record << ","
            end
            record << "\n"
            record << evaluator.evaluate(i).to_json
            parser << record
          end
          parser << "\n]\n"
        end
      end

      def execute_directive_eval(parser, line, content, options)
        groonga_command = content.split(" ", 2)[1]
        parser << "#{expand_variables(groonga_command)}\n"
      end

      def execute_directive_require_input_type(parser, line, content, options)
        input_type, = options
        unless @context.input_type == input_type
          omit("require input type: #{input_type}")
        end
      end

      def execute_directive_require_testee(parser, line, content, options)
        testee, = options
        unless @context.testee == testee
          omit("require testee: #{testee}")
        end
      end

      def execute_directive_require_interface(parser, line, content, options)
        interface, = options
        unless @context.interface == interface
          omit("require interface: #{interface}")
        end
      end

      def execute_directive_require_apache_arrow(parser, line, content, options)
        unless defined?(::Arrow)
          omit("require Apache Arrow")
        end
      end

      def compile_pattern(pattern)
        case pattern
        when /\A\/(.*)\/([ixm]*)?\z/
          content = $1
          options = $2
          regexp_flags = 0
          regexp_flags |= Regexp::IGNORECASE if options.include?("i")
          regexp_flags |= Regexp::EXTENDED if options.include?("x")
          regexp_flags |= Regexp::MULTILINE if options.include?("m")
          Regexp.new(content, regexp_flags)
        else
          log_error("# error: invalid pattern: #{pattern}")
          @context.error
        end
      end

      def execute_directive_add_ignore_log_pattern(parser, line, content, options)
        pattern = content.split(" ", 2)[1]
        @ignore_log_patterns[pattern] = compile_pattern(pattern)
      end

      def execute_directive_remove_ignore_log_pattern(parser, line, content, options)
        pattern = content.split(" ", 2)[1]
        @ignore_log_patterns.delete(pattern)
      end

      def execute_directive(parser, line, content)
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
        when "timeout"
          execute_directive_timeout(line, content, options)
        when "read-timeout"
          execute_directive_read_timeout(line, content, options)
        when "long-read-timeout"
          execute_directive_long_read_timeout(line, content, options)
        when "on-error"
          execute_directive_on_error(line, content, options)
        when "omit"
          execute_directive_omit(line, content, options)
        when "add-important-log-levels"
          execute_directive_add_important_log_levels(line, content, options)
        when "remove-important-log-levels"
          execute_directive_remove_important_log_levels(line, content, options)
        when "sleep"
          execute_directive_sleep(line, content, options)
        when "collect-query-log"
          execute_directive_collect_query_log(line, content, options)
        when "generate-series"
          execute_directive_generate_series(parser, line, content, options)
        when "eval"
          execute_directive_eval(parser, line, content, options)
        when "require-input-type"
          execute_directive_require_input_type(parser, line, content, options)
        when "require-testee"
          execute_directive_require_testee(parser, line, content, options)
        when "require-interface"
          execute_directive_require_interface(parser, line, content, options)
        when "require-apache-arrow"
          execute_directive_require_apache_arrow(parser, line, content, options)
        when "add-ignore-log-pattern"
          execute_directive_add_ignore_log_pattern(parser, line, content, options)
        when "remove-ignore-log-pattern"
          execute_directive_remove_ignore_log_pattern(parser, line, content, options)
        else
          log_input(line)
          log_error("#|e| unknown directive: <#{command}>")
        end
      end

      def execute_suggest_create_dataset(dataset_name)
        if @context.groonga_suggest_create_dataset.nil?
          omit("groonga-suggest-create-dataset isn't specified")
        end

        command_line = [
          @context.groonga_suggest_create_dataset,
          @context.db_path.to_s,
          dataset_name,
        ]
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

      def extract_command_info(command)
        @current_command = command
        if @current_command.name == "dump"
          @output_type = "groonga-command"
        else
          @output_type = @current_command[:output_type]
        end
      end

      def execute_command(command)
        command[:output_type] ||= @context.output_type
        extract_command_info(command)
        log_input("#{command.original_source}\n")
        timeout = @context.timeout
        response = nil
        begin
          Timeout.timeout(timeout) do
            response = send_command(command)
          end
        rescue Timeout::Error
          log_error("# error: timeout (#{timeout}s)")
          @context.error
        rescue => error
          log_error("# error: #{error.class}: #{error.message}")
          error.backtrace.each do |line|
            log_error("# error: #{line}")
          end
          log_error(read_all_log)
          @context.error
        else
          type = @output_type
          log_output(response)
          log_error(extract_important_messages(read_all_log))
          log_query_log_content(read_all_query_log)

          @context.error if error_response?(response, type)
        end
      end

      def read_all_log
        read_all_readable_content(context.log, :first_timeout => 0)
      end

      def read_all_query_log
        content = read_all_readable_content(context.query_log,
                                            first_timeout: 0)
        lines = content.lines
        unless lines.empty?
          timeout = Time.now + @context.read_timeout
          while Time.now < timeout
            break if /rc=-?\d+$/ =~ lines.last
            additional_content = read_all_readable_content(context.query_log,
                                                           first_timeout: 0)
            next if additional_content.empty?
            content << additional_content
            lines.concat(additional_content.lines)
          end
        end
        content
      end

      def extract_important_messages(log)
        important_messages = []
        parser = GroongaLog::Parser.new
        in_crash = false
        parser.parse(log) do |entry|
          if entry.log_level == :critical
            case entry.message
            when "-- CRASHED!!! --"
              in_crash = true
            when "----------------"
              in_crash = false
            end
          end

          next unless important_log_level?(entry.log_level)
          if @context.suppress_backtrace?
            next if !in_crash and backtrace_log_message?(entry.message)
          end
          next if thread_log_message?(entry.message)
          next if ignore_log_message?(entry.message)
          formatted_log_level = format_log_level(entry.log_level)
          important_messages << "\#|#{formatted_log_level}| #{entry.message}"
        end
        important_messages.join("\n")
      end

      def read_all_readable_content(output, options={})
        content = ""
        first_timeout = options[:first_timeout] || @context.read_timeout
        timeout = first_timeout
        while IO.select([output], [], [], timeout)
          break if output.eof?
          request_bytes = 4096
          read_content = output.readpartial(request_bytes)
          debug_output(read_content)
          content << read_content
          if read_content.bytesize < request_bytes
            if options[:stream_output]
              timeout = 0.1
            else
              timeout = 0
            end
          end
        end
        content
      end

      def important_log_level?(log_level)
        case log_level
        when :emergency, :alert, :critical, :error, :warning
          true
        when *@custom_important_log_levels
          true
        else
          false
        end
      end

      def format_log_level(log_level)
        case log_level
        when :emergency
          "E"
        when :alert
          "A"
        when :critical
          "C"
        when :error
          "e"
        when :warning
          "w"
        when :notice
          "n"
        when :information
          "i"
        when :debug
          "d"
        when :dump
          "-"
        end
      end

      def backtrace_log_message?(message)
        case message
        when /\A\//
          true
        when /\A[a-zA-Z]:[\/\\]/
          true
        when /\A\(unknown\):\d+:\d+: /
          true
        when /\A(?:groonga|groonga-httpd)
                \((?:\+0x\h+|\w+\+0x\h+)?\)
                \s
                \[0x\h+\]\z/x
          # groonga() [0x564caf2bfc12]
          # groonga(+0xbd1aa) [0x564caf2bfc12]
          # groonga-httpd(+0xbd1aa) [0x564caf2bfc12]
          # groonga-httpd(ngx_http_core_run_phases+0x25) [0x564caf2bfc12]
          true
        when /\A\d+\s+(?:lib\S+\.dylib|\S+\.so|groonga|nginx|\?\?\?)\s+
                0x[\da-f]+\s
                \S+\s\+\s\d+\z/x
          true
        else
          false
        end
      end

      def thread_log_message?(message)
        case message
        when /\Athread start/
          true
        when /\Athread end/
          true
        else
          false
        end
      end

      def ignore_log_message?(message)
        @ignore_log_patterns.any? do |_pattern, regexp|
          regexp === message
        end
      end

      def error_response?(response, type)
        status = nil
        begin
          status, = ResponseParser.parse(response, type)
        rescue ParseError
          return false
        end

        return_code, = status
        return_code != ReturnCode::SUCCESS
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

      def log_query(content)
        log_force(:query, content, {})
      end

      def log_query_log_content(content)
        return unless @context.collect_query_log?

        parser = GroongaQueryLog::Parser.new
        parser.parse(content) do |statistic|
          relative_elapsed_time = "000000000000000"
          command = statistic.command
          if command
            command[:output_type] = nil if command.output_type == :json
            log_query("\#>#{command.to_command_format}")
          end
          statistic.each_operation do |operation|
            message = operation[:raw_message]
            case operation[:name]
            when "cache"
              message = message.gsub(/\(\d+\)/, "(0)")
            when "send"
              message = message.gsub(/\(\d+\)(?:: \d+\/\d+)?\z/, "(0)")
            end
            log_query("\#:#{relative_elapsed_time} #{message}")
          end
          log_query("\#<#{relative_elapsed_time} rc=#{statistic.return_code}")
        end
      end

      def debug_input(input)
        return unless @context.debug?
        $stderr.puts("> #{input}")
      end

      def debug_output(output)
        if @context.debug?
          output.each_line do |line|
            $stderr.puts("< #{line}")
          end
        end
        output
      end

      def default_long_read_timeout
        180
      end
    end
  end
end
