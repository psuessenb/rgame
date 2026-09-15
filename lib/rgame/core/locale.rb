# frozen_string_literal: true

require 'rgame/core_ext'

module RGame
  # `RGame::Core.preferred_locales` is C (`ext/rgame_core/app/locale.c`, bound in
  # `ruby/locale_ext.c`): the user's preferred locales as the operating system
  # reports them through SDL, most preferred first.
  #
  #   RGame::Core.preferred_locales   # => ["de-AT", "en"]
  #
  # Each is a language, then a hyphen and a country when the OS names one. The
  # list is `[]` when the OS names none — on Linux, under `LANG=C`. It needs no
  # app: SDL reads it without being initialised, so it is a module function
  # rather than an `App` method.
  #
  # What it returns is taken as given. SDL on Linux reads `LANG` and then
  # `LANGUAGE`, and ignores `LC_ALL`, so the list can repeat a locale; choosing
  # among them is `RGame::Engine::I18n.choose`, which the glue calls.
  module Core
  end
end
