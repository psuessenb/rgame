# frozen_string_literal: true

require_relative 'object'

module RGame
  module Engine
    module Tiled
      # A `.tx` object template: an `<object>` that objects in a map name with
      # `template="…"` and borrow everything from.
      #
      # An instance's own attributes win, and so does its own shape. Its
      # properties merge with the template's by name, the instance's winning,
      # and each `file` property resolves against the file that states it. A
      # tile template's gid is counted from the template's own tileset, so
      # `apply` moves it to where that tileset sits in the map.
      class Template
        # Reads the `.tx` at `tx_path`, resolving its paths against it.
        def self.load(tx_path)
          root = Tiled.root(File.read(tx_path), 'template', tx_path)
          object = root.elements['object'] or Attributes.refuse_element(root, tx_path, 'holds no <object>')
          new(object, root.elements['tileset'], tx_path)
        end

        def initialize(object, tileset, source_path)
          @object = object
          @source_path = source_path
          @properties = Properties.parse(object.elements['properties'], source_path: source_path)
          @tileset_source = tileset && Attributes.path(tileset.attributes['source'].to_s, source_path)
          @tileset_firstgid = tileset && Attributes.integer!(tileset, 'firstgid', source_path)
        end

        # The `Object` `instance` means: this template with the instance's own
        # attributes, shape and properties over it. `source_path` is the map
        # the instance sits in. `firstgid_of` answers the firstgid the map gives
        # a `.tsx`, by its resolved path, or `nil` when the map names none.
        def apply(instance, source_path:, firstgid_of:)
          merged = @object.deep_clone
          instance.attributes.each_attribute { merged.add_attribute(it.name, it.value) unless it.name == 'template' }
          replace_shape(merged, instance)
          merged.delete_element('properties')
          merged.add_attribute('gid', map_gid(merged, source_path, firstgid_of).to_s) if borrows_gid?(instance)

          object = Object.parse(merged, source_path: source_path)
          own = Properties.parse(instance.elements['properties'], source_path: source_path)
          object.with(properties: own.empty? ? @properties : Properties.new(@properties.to_h.merge(own.to_h)))
        end

        private

        def replace_shape(merged, instance)
          shape = instance.elements[SHAPES] or return

          merged.elements[SHAPES]&.then { merged.delete_element(it) }
          merged.add_element(shape.deep_clone)
        end

        def borrows_gid?(instance) = instance.attributes['gid'].nil? && @object.attributes['gid']

        def map_gid(merged, source_path, firstgid_of)
          raw = Attributes.integer(merged, 'gid', @source_path)
          firstgid = @tileset_source && firstgid_of.call(@tileset_source)
          unless firstgid
            raise FormatError, "template #{@source_path} draws a tile from #{@tileset_source || 'no tileset'}, " \
                               "which #{source_path || 'the map'} does not name; add that tileset to the map in Tiled"
          end

          ((raw & GID_MASK) - @tileset_firstgid + firstgid) | (raw & FLIP_BITS)
        end
      end
    end
  end
end
