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

module Grntest
  class ExecutionContext
    attr_writer :logging
    attr_accessor :base_directory, :temporary_directory_path, :db_path
    attr_accessor :plugins_directory
    attr_accessor :plugin_extension
    attr_accessor :groonga_suggest_create_dataset
    attr_accessor :testee
    attr_accessor :interface
    attr_accessor :result
    attr_writer :use_http_post
    attr_writer :use_http_chunked
    attr_accessor :input_type
    attr_accessor :output_type
    attr_accessor :on_error
    attr_accessor :abort_tag
    attr_accessor :timeout
    attr_accessor :read_timeout
    attr_accessor :default_timeout
    attr_accessor :default_read_timeout
    attr_accessor :shutdown_wait_timeout
    attr_writer :suppress_backtrace
    attr_writer :collect_query_log
    attr_writer :debug
    def initialize
      @logging = true
      @base_directory = Pathname(".")
      @temporary_directory_path = Pathname("tmp")
      @db_path = Pathname("db")
      @plugins_directory = nil
      @plugin_extension = guess_plugin_extension
      @groonga_suggest_create_dataset = "groonga-suggest-create-dataset"
      @testee = "groonga"
      @interface = "stdio"
      @n_nested = 0
      @result = []
      @use_http_post = false
      @use_http_chunked = false
      @input_type = "json"
      @output_type = "json"
      @log = nil
      @query_log = nil
      @on_error = :default
      @abort_tag = nil
      @timeout = 0
      @read_timeout = 5
      @default_timeout = @timeout
      @default_read_timeout = @read_timeout
      @shutdown_wait_timeout = 5
      @omitted = false
      @suppress_backtrace = true
      @collect_query_log = false
      @debug = false
    end

    def logging?
      @logging
    end

    def use_http_post?
      @use_http_post
    end

    def use_http_chunked?
      @use_http_chunked
    end

    def suppress_backtrace?
      @suppress_backtrace or debug?
    end

    def collect_query_log?
      @collect_query_log
    end

    def debug?
      @debug
    end

    def execute
      @n_nested += 1
      yield
    ensure
      @n_nested -= 1
    end

    def top_level?
      @n_nested == 1
    end

    def log_path
      @temporary_directory_path + "groonga.log"
    end

    def log
      @log ||= File.open(log_path.to_s, "a+")
    end

    def query_log_path
      @temporary_directory_path + "groonga.query.log"
    end

    def query_log
      @query_log ||= File.open(query_log_path.to_s, "a+")
    end

    def relative_db_path
      @db_path.relative_path_from(@temporary_directory_path)
    end

    def libtool_directory
      @plugins_directory.find do |sub_path|
        if sub_path.directory? and sub_path.basename.to_s == ".libs"
          return ".libs/"
        end
      end
      ""
    end

    def omitted?
      @omitted
    end

    def error
      case @on_error
      when :omit
        omit
      end
    end

    def omit
      @omitted = true
      abort
    end

    def abort
      throw @abort_tag
    end

    def close_logs
      if @log
        @log.close
        @log = nil
      end

      if @query_log
        @query_log.close
        @query_log = nil
      end
    end

    private
    def guess_plugin_extension
      case RUBY_PLATFORM
      when /mingw|mswin/
        "dll"
      else
        "so"
      end
    end
  end
end
