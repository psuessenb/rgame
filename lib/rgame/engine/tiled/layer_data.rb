# frozen_string_literal: true

require 'zlib'
require_relative 'attributes'

module RGame
  module Engine
    module Tiled
      # Decodes a tile layer's `<data>`, or one `<chunk>` of it, into a flat
      # Array of gids in reading order, each passed through `Tiled.gid`.
      #
      # It reads every encoding Tiled writes: XML `<tile>` elements, CSV, and
      # base64 either uncompressed or compressed with gzip or zlib. It refuses
      # zstd, which would need a gem rgame does not carry, and a count of
      # tiles other than the one the element's size calls for.
      module LayerData
        module_function

        # The gids in `container`, a `<data>` element or a `<chunk>` inside
        # one. `data` is the `<data>` element, whose `encoding` and
        # `compression` hold for its chunks too. `count` is the number of tiles
        # the container must hold.
        def decode(container, data, count, source_path)
          gids = case data.attributes['encoding']
                 when nil then xml(container, source_path)
                 when 'csv' then csv(container, data, source_path)
                 when 'base64' then base64(container, data, source_path)
                 else Attributes.refuse(data, 'encoding', source_path, 'rgame does not read')
                 end
          return gids.map! { Tiled.gid(it) } if gids.size == count

          Attributes.refuse_element(container, source_path,
                                    "holds #{gids.size} tiles where its size calls for #{count}")
        end

        def xml(container, source_path)
          container.get_elements('tile').map { Attributes.integer(it, 'gid', source_path, default: 0) }
        end

        def csv(container, data, source_path)
          container.text.to_s.split(',').map { Integer(it.strip, 10) }
        rescue ArgumentError
          Attributes.refuse_element(data, source_path, 'holds CSV that is not a list of whole numbers')
        end

        def base64(container, data, source_path)
          bytes = container.text.to_s.strip.unpack1('m')
          decompressed = case data.attributes['compression']
                         when nil then bytes
                         when 'zlib' then Zlib::Inflate.inflate(bytes)
                         when 'gzip' then Zlib.gunzip(bytes)
                         when 'zstd'
                           Attributes.refuse(data, 'compression', source_path,
                                             'needs a gem rgame does not carry; ' \
                                             'choose zlib or gzip in the map properties in Tiled')
                         else Attributes.refuse(data, 'compression', source_path, 'rgame does not read')
                         end
          decompressed.unpack('V*')
        rescue Zlib::Error => e
          Attributes.refuse_element(data, source_path, "does not decompress as #{data.attributes['compression']}: " \
                                                       "#{e.message}")
        end
        private_class_method :xml, :csv, :base64
      end
    end
  end
end
