# frozen_string_literal: true

require 'rspec/core/rake_task'

# Two Ruby spec suites, deliberately two separate processes.
#
# `spec` must never load SDL/OpenGL: it covers RGame::Util and RGame::Engine,
# and the whole point of the engine layer is that it can be specified with no
# window and no graphics libraries in the process at all. `spec:core` is the
# one allowed to open real windows.
#
# They are separate directories with separate runners rather than one tree with
# an exclude rule, because a rule you have to remember is a rule that gets
# forgotten — see CLAUDE.md, "Design out misuse".

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

desc 'Run the C unit tests (Check)'
task :test do
  sh 'make test'
end

desc 'Everything: C tests, headless specs, Core specs'
task default: %i[test spec spec:core]
