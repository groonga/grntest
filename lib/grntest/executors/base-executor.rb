# Copyright (C) 2012-2014  Kouhei Sutou <kou@clear-code.com>
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

require "groonga/command/parser"

require "grntest/error"
require "grntest/log-parser"
require "grntest/query-log-parser"
require "grntest/execution-context"
require "grntest/response-parser"

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
        @current_command_name = nil
        @output_type = nil
        @long_timeout = default_long_timeout
        @context = context
        @custom_important_log_levels = []
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
                log_error("#{line_info}: #{$!.message}")
                if $!.is_a?(Groonga::Command::Parser::Error)
                  @context.abort
                else
                  log_error("#{line_info}: #{$!.message}")
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
          send_command(command("shutdown"))
        rescue
          return false
        end

        status = nil
        total_sleep_time = 0
        sleep_time = 0.1
        loop do
          _, status = Process.waitpid2(pid, Process::WNOHANG)
          break if status
          sleep(sleep_time)
          total_sleep_time += sleep_time
          return false if total_sleep_time > timeout
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
            execute_directive("\##{comment}", directive_content)
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
        string.gsub(/\#{(.+?)}/) do |matched|
          case $1
          when "db_path"
            @context.db_path.to_s
          else
            matched
          end
        end
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

      def execute_directive_long_timeout(line, content, options)
        long_timeout, = options
        invalid_value_p = false
        case long_timeout
        when "default"
          @long_timeout = default_long_timeout
        when nil
          invalid_value_p = true
        else
          begin
            @long_timeout = Float(long_timeout)
          rescue ArgumentError
            invalid_value_p = true
          end
        end

        if invalid_value_p
          log_input(line)
          message = "long-timeout must be number or 'default': <#{long_timeout}>"
          log_error("#|e| [long-timeout] #{message}")
        end
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
        level[0]
      end

      def execute_directive_sleep(line, content, options)
        time = options[0].to_f
        sleep(time) if time >= 0
      end

      def execute_directive_collect_query_log(line, content, options)
        @context.collect_query_log = (options[0] == "true")
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
        when "long-timeout"
          execute_directive_long_timeout(line, content, options)
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

      def extract_command_info(command)
        @current_command = command
        if @current_command.name == "dump"
          @output_type = "groonga-command"
        else
          @output_type = @current_command[:output_type] || @context.output_type
        end
      end

      def execute_command(command)
        extract_command_info(command)
        log_input("#{command.original_source}\n")
        begin
          response = send_command(command)
        rescue => error
          log_error("# error: #{error.class}: #{error.message}")
          error.backtrace.each do |line|
            log_error("# error: #{line}")
          end
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
        read_all_readable_content(context.query_log, :first_timeout => 0)
      end

      def extract_important_messages(log)
        important_messages = []
        parser = LogParser.new
        parser.parse(log) do |entry|
          next unless important_log_level?(entry.log_level)
          next if backtrace_log_message?(entry.message)
          important_messages << "\#|#{entry.log_level}| #{entry.message}"
        end
        important_messages.join("\n")
      end

      def read_all_readable_content(output, options={})
        content = ""
        first_timeout = options[:first_timeout] || 5
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

      def important_log_level?(log_level)
        ["E", "A", "C", "e", "w"].include?(log_level) or
          @custom_important_log_levels.include?(log_level)
      end

      def backtrace_log_message?(message)
        case message
        when /\A\//
          true
        when /\Agroonga\(\) \[0x[\da-f]+\]\z/
          true
        when /\A\d+\s+(?:lib\S+\.dylib|\S+\.so|groonga|nginx|\?\?\?)\s+
                0x[\da-f]+\s
                \S+\s\+\s\d+\z/x
          true
        else
          false
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

        parser = QueryLogParser.new
        parser.parse(content) do |entry|
          log_query("\##{entry.mark}#{entry.message}")
        end
      end

      def default_long_timeout
        180
      end
    end
  end
end
