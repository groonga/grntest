# Copyright (C) 2016  Kouhei Sutou <kou@clear-code.com>
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

module Grntest
  class VariableExpander
    def initialize(context)
      @context = context
    end

    def expand(string)
      string.gsub(/\#{(.+?)}/) do |matched|
        case $1
        when "db_path"
          @context.db_path.to_s
        when "db_directory"
          @context.db_path.parent.to_s
        when "base_directory"
          @context.base_directory.to_s
        else
          matched
        end
      end
    end
  end
end
