# Copyright (C) 2015  Kouhei Sutou <kou@clear-code.com>
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

require "grntest/query-log-entry"

module Grntest
  class QueryLogParser
    def parse(log)
      log.each_line do |line|
        case line
        when /\A(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)\|.+?\|(.)/
          timestamp = $1
          mark = $2
          message = normalize_message(mark, $POSTMATCH.chomp)
          entry = QueryLogEntry.new(timestamp, mark, message)
          yield(entry)
        end
      end
    end

    private
    def normalize_message(mark, message)
      case mark
      when ">"
        message = normalize_command(message)
      else
        message = normalize_elapsed_time(message)
        message = normalize_cache_content(message)
      end
      message
    end

    def normalize_command(message)
      command = Groonga::Command::Parser.parse(message)
      command.to_command_format
    end

    def normalize_elapsed_time(message)
      message.gsub(/\A\d{15} /, "0" * 15 + " ")
    end

    def normalize_cache_content(message)
      message.gsub(/\A(0{15}) (cache\()\d+(\))\z/) do
        "#{$1} #{$2}0#{$3}"
      end
    end
  end
end
