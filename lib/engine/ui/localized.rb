# frozen_string_literal: true

module Engine
  module UI
    # Mixin for widgets whose displayed text can come from an i18n key. A keyed widget
    # resolves through Engine::I18n and re-resolves only when the locale changes
    # (tracked by I18n.generation) — so a language switch updates every keyed widget on
    # its next draw, while steady-state draws stay allocation-free. Literal-text widgets
    # pass no key and never touch I18n.
    module Localized
      def init_localization(key, vars)
        @i18n_key = key
        @i18n_vars = vars || {}
        @i18n_generation = nil
      end

      def localized? = !@i18n_key.nil?

      # When keyed, yields the freshly resolved string the first time and after every
      # locale change (so the caller can store it and invalidate cached layout, e.g. a
      # measured width). A no-op for literal widgets.
      def refresh_localization
        return unless @i18n_key
        return if @i18n_generation == Engine::I18n.generation

        @i18n_generation = Engine::I18n.generation
        yield Engine::I18n.t(@i18n_key, **@i18n_vars)
      end
    end
  end
end
