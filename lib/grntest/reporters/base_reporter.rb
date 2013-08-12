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
  module Reporters
    class BaseReporter
      def initialize(tester)
        @tester = tester
        @term_width = guess_term_width
        @output = @tester.output
        @mutex = Mutex.new
        reset_current_column
      end

      private
      def synchronize
        @mutex.synchronize do
          yield
        end
      end

      def report_summary(result)
        puts(statistics_header)
        puts(colorize(statistics(result), result))
        pass_ratio = result.pass_ratio
        elapsed_time = result.elapsed_time
        summary = "%.4g%% passed in %.4fs." % [pass_ratio, elapsed_time]
        puts(colorize(summary, result))
      end

      def columns
        [
          # label,      format value
          ["tests/sec", lambda {|result| "%9.2f" % throughput(result)}],
          ["   tests",  lambda {|result| "%8d"   % result.n_tests}],
          ["  passes",  lambda {|result| "%8d"   % result.n_passed_tests}],
          ["failures",  lambda {|result| "%8d"   % result.n_failed_tests}],
          ["  leaked",  lambda {|result| "%8d"   % result.n_leaked_tests}],
          [" omitted",  lambda {|result| "%8d"   % result.n_omitted_tests}],
          ["!checked",  lambda {|result| "%8d"   % result.n_not_checked_tests}],
        ]
      end

      def statistics_header
        labels = columns.collect do |label, format_value|
          label
        end
        "  " + labels.join(" | ") + " |"
      end

      def statistics(result)
        items = columns.collect do |label, format_value|
          format_value.call(result)
        end
        "  " + items.join(" | ") + " |"
      end

      def throughput(result)
        if result.elapsed_time.zero?
          tests_per_second = 0
        else
          tests_per_second = result.n_tests / result.elapsed_time
        end
        tests_per_second
      end

      def report_failure(result)
        report_marker(result)
        report_diff(result.expected, result.actual)
        report_marker(result)
      end

      def report_actual(result)
        report_marker(result)
        puts(result.actual)
        report_marker(result)
      end

      def report_marker(result)
        puts(colorize("=" * @term_width, result))
      end

      def report_diff(expected, actual)
        create_temporary_file("expected", expected) do |expected_file|
          create_temporary_file("actual", actual) do |actual_file|
            diff_options = @tester.diff_options.dup
            diff_options.concat(["--label", "(expected)", expected_file.path,
                                 "--label", "(actual)", actual_file.path])
            system(@tester.diff, *diff_options)
          end
        end
      end

      def report_test(worker, result)
        report_marker(result)
        print("[#{worker.id}] ") if @tester.n_workers > 1
        puts(worker.suite_name)
        print("  #{worker.test_name}")
        report_test_result(result, worker.status)
      end

      def report_test_result(result, label)
        message = test_result_message(result, label)
        message_width = string_width(message)
        rest_width = @term_width - @current_column
        if rest_width > message_width
          print(" " * (rest_width - message_width))
        end
        puts(message)
      end

      def test_result_message(result, label)
        elapsed_time = result.elapsed_time
        formatted_elapsed_time = "%.4fs" % elapsed_time
        formatted_elapsed_time = colorize(formatted_elapsed_time,
                                          elapsed_time_status(elapsed_time))
        " #{formatted_elapsed_time} [#{colorize(label, result)}]"
      end

      LONG_ELAPSED_TIME = 1.0
      def long_elapsed_time?(elapsed_time)
        elapsed_time >= LONG_ELAPSED_TIME
      end

      def elapsed_time_status(elapsed_time)
        if long_elapsed_time?(elapsed_time)
          elapsed_time_status = :failure
        else
          elapsed_time_status = :not_checked
        end
      end

      def justify(message, width)
        return " " * width if message.nil?
        return message.ljust(width) if message.bytesize <= width
        half_width = width / 2.0
        elision_mark = "..."
        left = message[0, half_width.ceil - elision_mark.size]
        right = message[(message.size - half_width.floor)..-1]
        "#{left}#{elision_mark}#{right}"
      end

      def print(message)
        @current_column += string_width(message.to_s)
        @output.print(message)
      end

      def puts(*messages)
        reset_current_column
        @output.puts(*messages)
      end

      def reset_current_column
        @current_column = 0
      end

      def create_temporary_file(key, content)
        file = Tempfile.new("groonga-test-#{key}")
        file.print(content)
        file.close
        yield(file)
      end

      def guess_term_width
        Integer(guess_term_width_from_env || guess_term_width_from_stty || 79)
      rescue ArgumentError
        0
      end

      def guess_term_width_from_env
        ENV["COLUMNS"] || ENV["TERM_WIDTH"]
      end

      def guess_term_width_from_stty
        return nil unless STDIN.tty?

        case tty_info
        when /(\d+) columns/
          $1
        when /columns (\d+)/
          $1
        else
          nil
        end
      end

      def tty_info
        begin
          `stty -a`
        rescue SystemCallError
          nil
        end
      end

      def string_width(string)
        string.gsub(/\e\[[0-9;]+m/, "").size
      end

      def result_status(result)
        if result.respond_to?(:status)
          result.status
        else
          if result.n_failed_tests > 0
            :failure
          elsif result.n_leaked_tests > 0
            :leaked
          elsif result.n_omitted_tests > 0
            :omitted
          elsif result.n_not_checked_tests > 0
            :not_checked
          else
            :success
          end
        end
      end

      def colorize(message, result_or_status)
        return message unless @tester.use_color?
        if result_or_status.is_a?(Symbol)
          status = result_or_status
        else
          status = result_status(result_or_status)
        end
        case status
        when :success
          "%s%s%s" % [success_color, message, reset_color]
        when :failure
          "%s%s%s" % [failure_color, message, reset_color]
        when :leaked
          "%s%s%s" % [leaked_color, message, reset_color]
        when :omitted
          "%s%s%s" % [omitted_color, message, reset_color]
        when :not_checked
          "%s%s%s" % [not_checked_color, message, reset_color]
        else
          message
        end
      end

      def success_color
        escape_sequence({
                          :color => :green,
                          :color_256 => [0, 3, 0],
                          :background => true,
                        },
                        {
                          :color => :white,
                          :color_256 => [5, 5, 5],
                          :bold => true,
                        })
      end

      def failure_color
        escape_sequence({
                          :color => :red,
                          :color_256 => [3, 0, 0],
                          :background => true,
                        },
                        {
                          :color => :white,
                          :color_256 => [5, 5, 5],
                          :bold => true,
                        })
      end

      def leaked_color
        escape_sequence({
                          :color => :magenta,
                          :color_256 => [3, 0, 3],
                          :background => true,
                        },
                        {
                          :color => :white,
                          :color_256 => [5, 5, 5],
                          :bold => true,
                        })
      end

      def omitted_color
        escape_sequence({
                          :color => :blue,
                          :color_256 => [0, 0, 1],
                          :background => true,
                        },
                        {
                          :color => :white,
                          :color_256 => [5, 5, 5],
                          :bold => true,
                        })
      end

      def not_checked_color
        escape_sequence({
                          :color => :cyan,
                          :color_256 => [0, 1, 1],
                          :background => true,
                        },
                        {
                          :color => :white,
                          :color_256 => [5, 5, 5],
                          :bold => true,
                        })
      end

      def reset_color
        escape_sequence(:reset)
      end

      COLOR_NAMES = [
        :black, :red, :green, :yellow,
        :blue, :magenta, :cyan, :white,
      ]
      def escape_sequence(*commands)
        sequence = []
        commands.each do |command|
          case command
          when :reset
            sequence << "0"
          when :bold
            sequence << "1"
          when :italic
            sequence << "3"
          when :underline
            sequence << "4"
          when Hash
            foreground_p = !command[:background]
            if available_colors == 256
              sequence << (foreground_p ? "38" : "48")
              sequence << "5"
              sequence << pack_256_color(*command[:color_256])
            else
              color_parameter = foreground_p ? 3 : 4
              color_parameter += 6 if command[:intensity]
              color = COLOR_NAMES.index(command[:color])
              sequence << "#{color_parameter}#{color}"
            end
          end
        end
        "\e[#{sequence.join(';')}m"
      end

      def pack_256_color(red, green, blue)
        red * 36 + green * 6 + blue + 16
      end

      def available_colors
        case ENV["COLORTERM"]
        when "gnome-terminal"
          256
        else
          case ENV["TERM"]
          when /-256color\z/
            256
          else
            8
          end
        end
      end
    end
  end
end
