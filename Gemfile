# frozen_string_literal: true

source 'https://rubygems.org'
ruby file: '.ruby-version'

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
