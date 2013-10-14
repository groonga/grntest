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

require "open-uri"

require "grntest/executors/base-executor"

module Grntest
  module Executors
    class HTTPExecutor < BaseExecutor
      def initialize(host, port, context=nil)
        super(context)
        @host = host
        @port = port
      end

      def send_command(command)
        url = "http://#{@host}:#{@port}#{command.to_uri_format}"
        begin
          open(url) do |response|
            response_data = response.read
            response_data << "\n" unless response_data.empty?
            response_data
          end
        rescue OpenURI::HTTPError
          $!.io.read
        end
      end

      def ensure_groonga_ready
        n_retried = 0
        begin
          send_command(command("status"))
        rescue SystemCallError
          n_retried += 1
          sleep(0.1)
          retry if n_retried < 10
          raise
        end
      end

      def shutdown
        send_command(command("shutdown"))
      end

      def create_sub_executor(context)
        self.class.new(@host, @port, context)
      end

      private
      def command(command_line)
        Groonga::Command::Parser.parse(command_line)
      end
    end
  end
end
