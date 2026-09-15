# frozen_string_literal: true

require 'yaml'
require_relative 'i18n/template'
require_relative 'i18n/plural'
require_relative 'i18n/plural_rules'

module RGame
  module Engine
    # Translation tables and the current language, as one global module so a
    # node can resolve text from its constructor, before it is in any tree.
    #
    # Tables are read in Rails' YAML format — the top-level key is the locale,
    # nested keys below it — and compiled at load into one flat Hash per locale,
    # keyed by the dotted key, whose values are pre-parsed `%{var}` templates or,
    # for a key whose nested keys are CLDR plural categories, a set of them.
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

        # The locales a key is looked up in, in order: the current locale, each
        # shorter prefix of it, then the default — `[:'de-AT', :de, :en]`.
        # Rebuilt when the locale or the default changes, not per lookup.
        attr_reader :chain

        # Merges a YAML document in Rails' format into the loaded tables. One
        # document may hold several locales, and a locale loaded twice is merged
        # key by key rather than replaced. `source` names the file in errors.
        def load(yaml, source: nil)
          merge(YAML.safe_load(yaml, aliases: true, filename: source), source || 'translations')
        end

        # `load` for a Hash already in memory: `load_hash(en: { menu: { title: 'Menu' } })`.
        def load_hash(hash) = merge(hash, 'translations')

        # Switches the language. `de_AT`, `'de-at'` and `:'de-AT'` name the same
        # locale. A locale with no table of its own is allowed and resolves
        # through its chain, so `:'de-CH'` reads the `de` table.
        def locale=(locale)
          locale = normalize(locale)
          return if locale == @locale

          @locale = locale
          relink
        end

        # The last link of every chain, and the locale `choose` falls back to.
        def default=(locale)
          locale = normalize(locale)
          return if locale == @default

          @default = locale
          relink
        end

        # The canonical Symbol for a locale identifier: the language lowercase,
        # a region uppercase, a script capitalized, joined by hyphens —
        # `normalize('zh_hant_tw') # => :'zh-Hant-TW'`.
        def normalize(locale)
          language, *subtags = locale.to_s.split(/[-_]/)
          raise ArgumentError, "not a locale: #{locale.inspect}" if language.nil? || language.empty?

          subtags.map! { |subtag| subtag.length == 4 ? subtag.capitalize : subtag.upcase }
          subtags.unshift(language.downcase).join('-').to_sym
        end

        # The first of `preferred` — the player's languages, most wanted first —
        # that has a table for itself or a shorter prefix of itself, normalized
        # but not shortened: `choose(['fr-CA', 'de-AT'])` with a `de` table is
        # `:'de-AT'`. The default when none has.
        def choose(preferred)
          preferred.each do |candidate|
            locale = normalize(candidate)
            return locale if lineage(locale).any? { |link| @tables.key?(link) }
          end
          @default
        end

        # Sets how `language` (or a regional locale, which then wins over its
        # language) sorts a count into a plural category. The block receives
        # the count and returns one of `Plural::CATEGORIES`. Replaces a built-in
        # rule; lasts until `reset`.
        def plural_rule(language, &rule)
          raise ArgumentError, 'plural_rule needs a block' unless rule

          @plural_rules[normalize(language)] = rule
        end

        # The locales that have a table, in load order.
        def available = @tables.keys

        # The translation of `key` (or `scope.key`) with `vars` interpolated. A
        # pluralized key needs `count:`, and picks its form by the plural rule
        # of the table that supplied it, which is not always the current locale.
        # Allocates on every call: it is for code off the per-frame path.
        def t(key, scope: nil, **vars)
          key = scope ? "#{scope}.#{key}" : key.to_s
          template = lookup(key)
          return key unless template

          template = pluralize(key, template, vars) if template.is_a?(Plural)

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
          @chain = chain_for(@locale)
          @plural_rules = PluralRules::BUILT_IN.dup
        end

        private

        def relink
          @chain = chain_for(@locale)
          @generation += 1
        end

        def chain_for(locale) = (lineage(locale) << @default).uniq.freeze

        def lineage(locale)
          subtags = locale.name.split('-')
          subtags.size.downto(1).map { |length| subtags.first(length).join('-').to_sym }
        end

        def pluralize(key, plural, vars)
          raise ArgumentError, "#{key} is pluralized and needs count:" unless vars.key?(:count)

          count = vars[:count]
          plural.template_for(count, plural_category(plural.locale, count))
        end

        def plural_category(locale, count)
          language = lineage(locale).find { |link| @plural_rules.key?(link) }
          @plural_rules.fetch(language, PluralRules::DEFAULT).call(count)
        end

        def lookup(key)
          @chain.each do |link|
            entry = @tables[link]&.[](key)
            return entry if entry
          end
          nil
        end

        def merge(hash, source)
          raise ArgumentError, "#{source}: expected a Hash of locales" unless hash.is_a?(Hash)

          hash.each do |locale, entries|
            raise ArgumentError, "#{source}: #{locale} must hold a Hash of keys" unless entries.is_a?(Hash)

            locale = normalize(locale)
            @sources[locale] = deep_merge(@sources.fetch(locale, {}), stringify(entries, locale.to_s, source))
            @tables[locale] = compile(@sources[locale], locale)
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

        def compile(entries, locale, prefix = nil, table = {})
          entries.each do |name, value|
            key = prefix ? "#{prefix}.#{name}" : name
            if !value.is_a?(Hash) then table[key.freeze] = Template.compile(value)
            elsif Plural.forms?(value) then table[key.freeze] = Plural.new(locale, value)
            else compile(value, locale, key, table)
            end
          end
          prefix ? table : table.freeze
        end
      end

      reset
    end
  end
end
