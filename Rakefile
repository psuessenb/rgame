# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

if File.exist?('.git') && `git config --get core.hooksPath`.strip.empty?
  system('git', 'config', 'core.hooksPath', '.githooks', exception: true)
end

RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = 'spec/**/*_spec.rb'
end

namespace :spec do
  desc 'Run the RGame::Core specs (opens real windows; boots its own Xvfb)'
  RSpec::Core::RakeTask.new(:core) do |t|
    t.pattern = 'spec_core/**/*_spec.rb'
    t.rspec_opts = '--options .rspec-core'
  end
end

namespace :docs do
  desc 'List public classes and methods docs/api never names and nothing tags @api private (needs make ext)'
  task :coverage do
    ruby 'tools/doc_coverage.rb'
  end
end

namespace :drive do
  desc 'Drive every example and test project, and fail one that allocates over its budget (boots Xvfb)'
  task :allocations do
    ruby 'tools/drive_allocations.rb'
  end
end

desc 'Run the C unit tests (Check)'
task :test do
  sh 'make test'
end

desc 'Everything: C tests, headless specs, Core specs'
task default: %i[test spec spec:core]
