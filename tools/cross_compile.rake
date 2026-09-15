# frozen_string_literal: true

require 'rake/extensiontask'
require_relative '../rakelib/sdl2_build'

# rake-compiler's cross-compile tasks for both extensions, with core_ext
# linking the static SDL2 `rake sdl2` builds. Run inside the rake-compiler-dock
# x86_64-linux-gnu image, whose cross Ruby links no libruby and whose glibc is
# old enough for the binary to load on older distributions:
#
#   rake -f tools/cross_compile.rake sdl2 compile:x86_64-linux-gnu
#
# The binaries land in tmp/x86_64-linux-gnu/stage/lib/rgame/. It is a rakefile
# of its own rather than part of the Rakefile, because rake-compiler warns about
# the objects `make ext` leaves in ext/ on every rake invocation, and because
# the image has no bundle to load the Rakefile's RSpec tasks from.
module CrossCompile
  EXTENSIONS = { 'rgame_util' => 'util_ext', 'rgame_core' => 'core_ext' }.freeze
  PLATFORMS = %w[x86_64-linux-gnu].freeze
end

gemspec = Gem::Specification.load(File.expand_path('../rgame.gemspec', __dir__))

CrossCompile::EXTENSIONS.each do |dir, name|
  Rake::ExtensionTask.new(name, gemspec) do |ext|
    ext.ext_dir = "ext/#{dir}"
    ext.lib_dir = 'lib/rgame'
    ext.cross_compile = true
    ext.cross_platform = CrossCompile::PLATFORMS
    ext.config_options << "--with-sdl2-static=#{SDL2_PREFIX}" if name == 'core_ext'
  end
end
