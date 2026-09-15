# frozen_string_literal: true

require_relative 'sdl2_build'

directory SDL2Build::BUILD_DIR

file SDL2Build::TARBALL => SDL2Build::BUILD_DIR do |t|
  partial = "#{t.name}.part"
  SDL2Build.download(SDL2Build::URL, partial)
  SDL2Build.verify(partial)
  mv partial, t.name
end

desc "Build the pinned SDL2 (#{SDL2_RELEASE[:version]}) as a static, position-independent library in build/sdl2"
task sdl2: "#{SDL2_PREFIX}/lib/pkgconfig/sdl2.pc"

file "#{SDL2_PREFIX}/lib/pkgconfig/sdl2.pc" => [SDL2Build::TARBALL, __FILE__, "#{__dir__}/sdl2_build.rb"] do |t|
  SDL2Build.verify(SDL2Build::TARBALL)

  rm_rf [SDL2Build::SOURCE_DIR, SDL2Build::CMAKE_DIR, SDL2_PREFIX]
  mkdir_p SDL2Build::SOURCE_DIR
  sh(*SDL2Build.unpack_command, chdir: SDL2Build::BUILD_DIR)

  sh 'cmake', '-S', File.join(SDL2Build::SOURCE_DIR, SDL2Build::NAME), '-B', SDL2Build::CMAKE_DIR,
     *SDL2Build.generator, *SDL2Build.cmake_options, "-DCMAKE_INSTALL_PREFIX=#{SDL2_PREFIX}"
  sh 'cmake', '--build', SDL2Build::CMAKE_DIR, '--parallel'
  sh 'cmake', '--install', SDL2Build::CMAKE_DIR
  touch t.name
end
