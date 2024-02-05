# Copyright (C) 2012-2024  Sutou Kouhei <kou@clear-code.com>
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
  class BaseResult
    attr_accessor :cpu_elapsed_time
    attr_accessor :real_elapsed_time
    def initialize
      @cpu_elapsed_time = 0
      @real_elapsed_time = 0
    end

    def measure
      cpu_start_time = Process.times
      real_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      cpu_finish_time = Process.times
      real_finish_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @cpu_elapsed_time =
        (cpu_finish_time.utime - cpu_start_time.utime) +
        (cpu_finish_time.stime - cpu_start_time.stime) +
        (cpu_finish_time.cutime - cpu_start_time.cutime) +
        (cpu_finish_time.cstime - cpu_start_time.cstime)
      @real_elapsed_time = real_finish_time - real_start_time
    end
  end
end
