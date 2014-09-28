# Copyright (C) 2014  Kouhei Sutou <kou@clear-code.com>
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

require "grntest/log-entry"

module Grntest
  class LogParser
    def parse(log)
      timestamp = nil
      log_level = nil
      message = nil
      emit_entry = lambda do
        if timestamp
          entry = LogEntry.new(timestamp, log_level, message.chomp)
          yield(entry)
        end
      end
      log.each_line do |line|
        case line
        when /\A(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)\|([a-zA-Z])\|\s*/
          emit_entry.call
          timestamp = $1
          log_level = $2
          message = $POSTMATCH
        else
          message << line
        end
      end
      emit_entry.call
    end
  end
end
