# frozen_string_literal: true

require_relative 'lib/rgame/version'

Gem::Specification.new do |spec|
  spec.name = 'rgame'
  spec.version = RGame::VERSION
  spec.authors = ['Paul Süßenbach']
  spec.email = ['2452696+psuessenb@users.noreply.github.com']
  spec.license = 'MIT'
  spec.homepage = 'https://github.com/psuessenb/rgame'

  spec.summary = 'A 2D game engine in C on SDL2 and OpenGL, exposed to Ruby.'
  spec.description = <<~DESCRIPTION
    RGame is a small 2D game engine for Ruby, written in Ruby and C. It's build
    on top of SDL2, OpenGL and miniaudio. It's built with testability and
    performance in mind, and aims to be an engine where you can write your whole
    game code in Ruby, test it as usual with RSpec (or Minitest, or another test
    framework) and still have acceptable performance.

    While still a work in progress, RGame aims to be more than a SDL/OpenGL
    binding - it ships with high level features like a scene graph, sprites,
    collision systems, debugging tools and an UI toolkit.
  DESCRIPTION

  spec.metadata = {
    'source_code_uri' => spec.homepage,
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'documentation_uri' => "#{spec.homepage}/blob/main/docs/api/README.md",
    'changelog_uri' => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'rubygems_mfa_required' => 'true'
  }

  spec.required_ruby_version = '>= 4.0'

  spec.extensions = [
    'ext/rgame_util/extconf.rb',
    'ext/rgame_core/extconf.rb'
  ]

  spec.require_paths = ['lib']

  spec.bindir = 'exe'
  spec.executables = ['rgame']

  packaged = %w[
    lib/**/*
    ext/**/*
    exe/**/*
    examples/**/*
    docs/api/**/*
    README.md
    CHANGELOG.md
    LICENSE
  ]

  artifacts = %r{
    \.(so|bundle|dylib|o|a|log)\z    # compiled output, and mkmf.log
    | \Aext/[^/]+/Makefile\z         # written by extconf.rb, not by us
    | \.dSYM/                        # macOS debug symbols — see below
  }x

  root = __dir__

  spec.files = Dir.glob(packaged, base: root)
                  .select { |path| File.file?(File.join(root, path)) }
                  .grep_v(artifacts)
                  .sort
end
