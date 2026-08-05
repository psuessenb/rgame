# frozen_string_literal: true

require 'yaml'

module Engine
  # Minimal localization: per-locale translation tables (loaded from YAML or a Hash),
  # `t(key)` with `%{var}` interpolation and a fallback locale, and a `generation`
  # counter that ticks whenever the locale changes — so cached UI text knows when to
  # re-resolve without polling every frame. A global module (like EventDispatcher),
  # so `t` is reachable anywhere. Pure Ruby; YAML is the only (stdlib) dependency.
  module I18n
    class << self
      attr_reader :generation

      # The locale `t` falls back to when the current locale lacks a key.
      def default = @fallback

      def default=(locale)
        @fallback = locale.to_sym
      end

      def reset
        @locales = {}
        @current = :en
        @fallback = :en
        @generation = 0
      end

      # Register a locale's translations (nested Hashes allowed). Keys are symbolized
      # so YAML ("string keys") and inline symbol keys look the same to `t`.
      def load(locale, translations)
        @locales[locale.to_sym] = symbolize(translations)
        self
      end

      def load_file(locale, path)
        load(locale, YAML.load_file(path))
      end

      def locale = @current

      # Switching the locale bumps the generation so observers re-resolve their text.
      def locale=(locale)
        locale = locale.to_sym
        return if locale == @current

        @current = locale
        @generation += 1
      end

      def available = @locales.keys

      # Resolve a dotted key ("menu.title" or :menu_title) in the current locale, then
      # the fallback locale, then the key itself; interpolate %{var} from `vars`.
      #
      # Pass `count:` to pluralize: the key's value is then a table of forms
      # ({ one:, other:, optionally zero: }), and `count` is also exposed to
      # interpolation as %{count}. English/German use the one/other rule.
      def t(key, count: nil, **vars)
        value = lookup(@current, key) || lookup(@fallback, key)
        value = pluralize(value, count) if count && value.is_a?(Hash)
        return key.to_s unless value.is_a?(String)

        vars = vars.merge(count: count) if count
        vars.empty? ? value : (value % vars)
      end

      private

      def pluralize(forms, count)
        return forms[:zero] if count.zero? && forms.key?(:zero)

        forms[count == 1 ? :one : :other] || forms[:other]
      end

      def lookup(locale, key)
        node = @locales[locale]
        key.to_s.split('.').each do |segment|
          return nil unless node.is_a?(Hash)

          node = node[segment.to_sym]
        end
        node
      end

      def symbolize(value)
        return value unless value.is_a?(Hash)

        value.to_h { |k, v| [k.to_sym, symbolize(v)] }
      end
    end

    reset
  end
end
