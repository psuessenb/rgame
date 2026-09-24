# frozen_string_literal: true

# Something a hero carries: a coin, or the hat the chest gives.
#
# `slot` is where it is worn, or nil for something that is only carried. `color`
# is what the hero draws it in while worn. A test project draws Strings, so
# `name` is the word both the bag and the hero draw.
class Item
  attr_reader :name, :slot, :color

  def initialize(name, slot: nil, color: nil)
    @name = name
    @slot = slot
    @color = color
  end

  def wearable? = !@slot.nil?
end
