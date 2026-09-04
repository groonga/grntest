# Copyright (C) 2016-2023  Sutou Kouhei <kou@clear-code.com>
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
  class TemplateEvaluator
    def initialize(template, *variable_names)
      @template = template
      @compiled = eval(<<-TEMPLATE)
        lambda do |#{variable_names.join(", ")}|
#{@template}
        end
      TEMPLATE
    end

    def evaluate(*values)
      @compiled.call(*values)
    end
  end
end
