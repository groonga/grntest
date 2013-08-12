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

module Grntest
  class Error < StandardError
  end

  class NotExist < Error
    attr_reader :path
    def initialize(path)
      @path = path
      super("<#{path}> doesn't exist.")
    end
  end

  class ParseError < Error
    attr_reader :type, :content, :reason
    def initialize(type, content, reason)
      @type = type
      @content = content
      @reason = reason
      super("failed to parse <#{@type}> content: #{reason}: <#{content}>")
    end
  end
end
