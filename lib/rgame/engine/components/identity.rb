# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A stable name for one node, so something outside the tree can refer to it.
      #
      #   sheep.add_component(Identity.new(id: 7))
      #   Identity.of(sheep)   # => 7
      #
      # ## What it is for, and what does not need it
      #
      # Most saving needs no identity at all. A scene is a recipe and a save file
      # is state: the scene rebuilds itself identically, and the save supplies the
      # few facts that differ. A *singular* thing needs no id because the variable
      # holding it is one — `@dog` is set where the dog is built and written
      # straight to on load. *Interchangeable* things need none either, because
      # their order will do: an array of positions restored in order is correct
      # precisely when swapping two of them changes nothing observable.
      #
      # This is for the case those two do not cover:
      #
      # - **members of a collection that can die**, where each survivor keeps
      #   state of its own. An array index stops meaning anything the first time
      #   the middle of the list is removed;
      # - **a reference from one saved thing to another** — a dog chasing a
      #   particular sheep. A node reference cannot be written to a file, and this
      #   is what it is written *as*.
      #
      # The second is the one that genuinely forces ids. A collection could always
      # be respawned from its own records; a reference between two of them could
      # not.
      #
      # ## The engine supplies the mechanism, a game supplies the meaning
      #
      # What gets an id, what the ids are, and how they are handed out are the
      # game's business — the same division as `Timer`, which counts down without
      # an opinion about what happens next. Two things follow from that, and both
      # are the game's to get right:
      #
      # **Ids must be unique among the things that can refer to each other.** This
      # component checks nothing; a duplicate is a save that restores the wrong
      # object, silently.
      #
      # **The allocator belongs in the save.** A counter that restarts at 1 on
      # load will reissue ids that the restored objects are already using, and the
      # collision surfaces later as a reference pointing at the wrong thing. Save
      # the next id alongside the objects and restore it too — it is one number,
      # and forgetting it is the classic way this goes wrong.
      class Identity < Engine::Component
        attr_reader :id

        def initialize(id:)
          super()
          raise ArgumentError, 'an identity needs an id' if id.nil?

          @id = id
        end

        # The id of a node, or nil for one that carries no identity.
        #
        # This is the direction that matters at save time: a component holding a
        # *node* — `Targeting#target` is the worked example — has to turn it into
        # something writable, and it has only the node to go on. Going the other
        # way is a game's own lookup, because only the game knows which
        # collection to search.
        def self.of(node)
          node&.get_component(self)&.id
        end
      end
    end
  end
end
