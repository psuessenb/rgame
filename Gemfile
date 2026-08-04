# frozen_string_literal: true

source 'https://rubygems.org'
ruby file: '.ruby-version'

# rgame itself, from this checkout. The gem has no runtime dependencies — it
# needs SDL2 and OpenGL, which are system libraries rather than gems — so this
# adds nothing to install; it is here so the gemspec is resolved and validated
# on every `bundle install`, and so `bundle exec` can see the gem.
#
# It does not build the extensions: Bundler leaves a path gem's extensions
# alone, and `make ext` stays the one mechanism that compiles them into
# lib/rgame/. Everything below is development-only.
gemspec

# Not a default gem since Ruby 4.0, so it must be declared to be usable under
# bundler. The Core specs use it to call X11/SDL C functions directly (synthetic
# keystrokes, virtual gamepads) with no native extension of their own.
gem 'base64'
gem 'fiddle'
gem 'gosu'
gem 'rake', require: false
gem 'rexml'
gem 'rubocop', require: false
gem 'rubocop-performance', require: false
gem 'rubocop-rspec', require: false
gem 'zlib'

group :test do
  gem 'rspec'
end
