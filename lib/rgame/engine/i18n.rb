# frozen_string_literal: true

require 'yaml'
require_relative 'i18n/template'

module RGame
  module Engine
    # Translation tables and the current language, as one global module so a
    # node can resolve text from its constructor, before it is in any tree.
    #
    # Tables are read in Rails' YAML format — the top-level key is the locale,
    # nested keys below it — and compiled at load into one flat Hash per locale,
    # keyed by the dotted key, whose values are pre-parsed `%{var}` templates.
    # `generation` moves whenever what a key resolves to may have changed, so
    # cached text compares one Integer instead of looking anything up.
    #
    # `I18n` parses Strings and never opens a file: finding and reading locale
    # files is the asset manager's job.
    module I18n
      class << self
        # An Integer that moves on every `load` and every change of locale.
        attr_reader :generation

        attr_reader :locale, :default

        # Merges a YAML document in Rails' format into the loaded tables. One
        # document may hold several locales, and a locale loaded twice is merged
        # key by key rather than replaced. `source` names the file in errors.
        def load(yaml, source: nil)
          merge(YAML.safe_load(yaml, aliases: true, filename: source), source || 'translations')
        end

        # `load` for a Hash already in memory: `load_hash(en: { menu: { title: 'Menu' } })`.
        def load_hash(hash) = merge(hash, 'translations')

        def locale=(locale)
          locale = locale.to_sym
          return if locale == @locale

          @locale = locale
          @generation += 1
        end

        def default=(locale)
          locale = locale.to_sym
          return if locale == @default

          @default = locale
          @generation += 1
        end

        # The locales that have a table, in load order.
        def available = @tables.keys

        # The translation of `key` (or `scope.key`) with `vars` interpolated.
        # Allocates on every call: it is for code off the per-frame path.
        def t(key, scope: nil, **vars)
          key = scope ? "#{scope}.#{key}" : key.to_s
          template = @tables.dig(@locale, key) || @tables.dig(@default, key)
          return key unless template

          missing = template.names.find { |name| !vars.key?(name) }
          raise ArgumentError, "#{key} needs %{#{missing}}" if missing

          template.render(vars)
        end

        # Forgets every table and restores the starting locale and default,
        # `:en`. The generation moves rather than restarting, so text cached
        # before a reset never mistakes itself for current.
        def reset
          @tables = {}
          @sources = {}
          @locale = :en
          @default = :en
          @generation = (@generation || 0) + 1
        end

        private

        def merge(hash, source)
          raise ArgumentError, "#{source}: expected a Hash of locales" unless hash.is_a?(Hash)

          hash.each do |locale, entries|
            raise ArgumentError, "#{source}: #{locale} must hold a Hash of keys" unless entries.is_a?(Hash)

            locale = locale.to_sym
            @sources[locale] = deep_merge(@sources.fetch(locale, {}), stringify(entries, locale.to_s, source))
            @tables[locale] = compile(@sources[locale])
          end
          @generation += 1
          self
        end

        def stringify(entries, path, source)
          entries.to_h do |name, value|
            name = scalar_name(name, path, source)
            here = "#{path}.#{name}"
            [name, value.is_a?(Hash) ? stringify(value, here, source) : scalar_value(value, here, source)]
          end
        end

        def scalar_name(name, path, source)
          return name.to_s if name.is_a?(String) || name.is_a?(Symbol) || name.is_a?(Integer)

          raise ArgumentError, "#{source}: #{path} has the key #{name.inspect}; " \
                               'YAML reads yes/no/on/off/true/false/~ unquoted, so quote it'
        end

        def scalar_value(value, path, source)
          return value.to_s if value.is_a?(String) || value.is_a?(Numeric)

          raise ArgumentError, "#{source}: #{path} is #{value.inspect}, not text; " \
                               'quote it if it is meant as a string'
        end

        def deep_merge(into, from)
          into.merge(from) do |_name, old, new|
            old.is_a?(Hash) && new.is_a?(Hash) ? deep_merge(old, new) : new
          end
        end

        def compile(entries, prefix = nil, table = {})
          entries.each do |name, value|
            key = prefix ? "#{prefix}.#{name}" : name
            value.is_a?(Hash) ? compile(value, key, table) : table[key.freeze] = Template.compile(value)
          end
          prefix ? table : table.freeze
        end
      end

      reset
    end
  end
end
