# frozen_string_literal: true

# Project bootstrap. Require this first from every entry point.
#
# Enables YJIT, Ruby's JIT compiler, for a meaningful speedup in the game loop.
# Guarded so the project still runs on a Ruby built without YJIT (it just runs
# unaccelerated instead of crashing).
RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enable)
