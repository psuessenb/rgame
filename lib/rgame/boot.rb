# frozen_string_literal: true

# Turns on YJIT, Ruby's JIT compiler, for a meaningful speedup in the game loop.
#
# Required by RGame::Game rather than left to each game to remember, because a
# game loop is the case JIT was built for and forgetting costs frames silently.
# It is deliberately *not* required by `rgame` or `rgame/core`: enabling a JIT
# is a decision about the whole process, and a library has no business making
# it for a host that only wanted a Color.
#
# Guarded, so the project still runs on a Ruby built without YJIT — it just runs
# unaccelerated instead of crashing.
RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enable)
