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

require "net/http"
require "open-uri"

require "grntest/executors/base-executor"

module Grntest
  module Executors
    class HTTPExecutor < BaseExecutor
      def initialize(host, port, context)
        super(context)
        @host = host
        @port = port
      end

      def send_command(command)
        if command.name == "load"
          send_load_command(command)
        else
          send_normal_command(command)
        end
      end

      def ensure_groonga_ready
        n_retried = 0
        begin
          send_command(command("status"))
        rescue Error
          n_retried += 1
          sleep(0.1)
          retry if n_retried < 100
          raise
        end
      end

      def create_sub_executor(context)
        self.class.new(@host, @port, context)
      end

      private
      MAX_URI_SIZE = 4096
      def send_load_command(command)
        lines = command.original_source.lines
        if lines.size == 1 and command.to_uri_format.size <= MAX_URI_SIZE
          return send_normal_command(command)
        end

        case @context.input_type
        when "apache-arrow"
          command[:input_type] = "apache-arrow"
          content_type = "application/x-apache-arrow-streaming"
          arrow_table = command.build_arrow_table
          if arrow_table
            buffer = Arrow::ResizableBuffer.new(1024)
            arrow_table.save(buffer, format: :stream)
            body = buffer.data.to_s
          else
            body = ""
          end
          command.arguments.delete(:values)
        else
          content_type = "application/json; charset=UTF-8"
          values = command.arguments.delete(:values)
          if lines.size >= 2 and lines[1].start_with?("[")
            unless /\s--columns\s/ =~ lines.first
              command.arguments.delete(:columns)
            end
            body = lines[1..-1].join
          else
            body = values
          end
        end
        request = Net::HTTP::Post.new(command.to_uri_format)
        request.content_type = content_type
        request.body = body
        response = Net::HTTP.start(@host, @port) do |http|
          http.read_timeout = read_timeout
          http.request(request)
        end
        normalize_response_data(command, response.body)
      end

      def send_normal_command(command)
        path_with_query = command.to_uri_format
        if @context.use_http_post?
          path, query = path_with_query.split("?", 2)
          request = Net::HTTP::Post.new(path)
          request.content_type = "application/x-www-form-urlencoded"
          request.body = query
        else
          request = Net::HTTP::Get.new(path_with_query)
        end
        url = "http://#{@host}:#{@port}#{path_with_query}"
        begin
          response = Net::HTTP.start(@host, @port) do |http|
            http.read_timeout = read_timeout
            http.request(request)
          end
          normalize_response_data(command, response.body)
        rescue SystemCallError
          message = "failed to read response from Groonga: <#{url}>: #{$!}"
          raise Error.new(message)
        rescue Net::HTTPBadResponse
          message = "bad response from Groonga: <#{url}>: "
          message << "#{$!.class}: #{$!.message}"
          raise Error.new(message)
        rescue Net::HTTPHeaderSyntaxError
          message = "bad HTTP header syntax in Groonga response: <#{url}>: "
          message << "#{$!.class}: #{$!.message}"
          raise Error.new(message)
        end
      end

      def normalize_response_data(command, raw_response_data)
        if raw_response_data.empty? or command.output_type == :none
          raw_response_data
        else
          "#{raw_response_data}\n"
        end
      end

      def read_timeout
        if @context.timeout.zero?
          nil
        else
          @context.timeout
        end
      end
    end
  end
end
