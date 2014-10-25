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

require "grntest/executors/base-executor"

module Grntest
  module Executors
    class StandardIOExecutor < BaseExecutor
      def initialize(input, output, context=nil)
        super(context)
        @input = input
        @output = output
      end

      def send_command(command)
        command_line = @current_command.original_source
        unless @current_command.has_key?(:output_type)
          command_line = command_line.sub(/$/, " --output_type #{@output_type}")
        end
        begin
          @input.print(command_line)
          @input.print("\n")
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
        options = {}
        options[:first_timeout] = @long_timeout if may_slow_command?
        read_all_readable_content(@output, options)
      end

      MAY_SLOW_COMMANDS = [
        "column_create",
        "register",
        "load",
      ]
      def may_slow_command?
        MAY_SLOW_COMMANDS.include?(@current_command.name)
      end
    end
  end
end
