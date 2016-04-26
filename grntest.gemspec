# -*- mode: ruby; coding: utf-8 -*-
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

clean_white_space = lambda do |entry|
  entry.gsub(/(\A\n+|\n+\z)/, '') + "\n"
end

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), "lib"))
require "grntest/version"

Gem::Specification.new do |spec|
  spec.name = "grntest"
  spec.version = Grntest::VERSION
  spec.homepage = "https://github.com/groonga/grntest"
  spec.authors = ["Kouhei Sutou", "Haruka Yoshihara"]
  spec.email = ["kou@clear-code.com", "yoshihara@clear-code.com"]
  readme = File.read("README.md")
  readme.force_encoding("UTF-8") if readme.respond_to?(:force_encoding)
  entries = readme.split(/^\#\#\s(.*)$/)
  description = clean_white_space.call(entries[entries.index("Description") + 1])
  spec.summary, spec.description, = description.split(/\n\n+/, 3)
  spec.license = "GPL-3.0+"
  spec.files = ["README.md", "Rakefile", "Gemfile", "#{spec.name}.gemspec"]
  spec.files += [".yardopts"]
  spec.files += Dir.glob("lib/**/*.rb")
  spec.files += Dir.glob("doc/text/*")
  spec.test_files += Dir.glob("test/**/*")
  Dir.chdir("bin") do
    spec.executables = Dir.glob("*")
  end

  spec.add_runtime_dependency("json")
  spec.add_runtime_dependency("msgpack")
  spec.add_runtime_dependency("diff-lcs")
  spec.add_runtime_dependency("groonga-command-parser")

  spec.add_development_dependency("bundler")
  spec.add_development_dependency("rake")
  spec.add_development_dependency("test-unit", ">= 3.0.0")
  spec.add_development_dependency("test-unit-rr")
  spec.add_development_dependency("packnga")
  spec.add_development_dependency("redcarpet")
end
