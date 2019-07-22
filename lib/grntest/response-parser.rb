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

require "json"
require "msgpack"

require "grntest/error"

module Grntest
  class ResponseParser
    class << self
      def parse(content, type)
        parser = new(type)
        parser.parse(content)
      end
    end

    def initialize(type)
      @type = type
    end

    def parse(content)
      case @type
      when "json", "msgpack"
        parse_result(content)
      else
        content
      end
    end

    def parse_result(result)
      case @type
      when "json"
        begin
          JSON.parse(result.chomp)
        rescue JSON::ParserError
          raise ParseError.new(@type, result, $!.message)
        end
      when "msgpack"
        begin
          MessagePack.unpack(result)
        rescue MessagePack::UnpackError, NoMemoryError, EOFError, ArgumentError
          raise ParseError.new(@type, result, $!.message)
        end
      else
        raise ParseError.new(@type, result, "unknown type")
      end
    end
  end
end
