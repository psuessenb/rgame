# The requirement, as given

Kept verbatim. The plan answers it point by point.

> Make a proper plan for this. The premisse is already outdated, as the
> `text-measurements` plan was finished with the last commits - so
> `Util::Typeface` exists, as well as `Engine::Paragraph`. And the sketch mixes
> up two things which the plan should divide cleanly:
>
> * A dialogue tree, or rather a decision graph - it's both not really a tree
>   (you can go back in dialogue), and it can probably be re-used for tracking
>   complex quest states. It needs nodes (careful naming is required here, to
>   not get them confused with the nodes of the scene graph - both in code and
>   in the minds of the users). This is basically a state machine, and part of
>   the research needs to be if it makes sense to include a simple
>   implementation of if ourselves, or if it's just better to point at existing
>   gems here. I personally find them quite complex, so I lean towards "include
>   a simple state machine implementation that's easy to learn and use". Either
>   way the state machine needs to support conditonal branches: Options that are
>   only available under certain conditions - so for instance a diaogue option
>   to bribe, but only if the player has enough money. If the option is even
>   displayed if the condition is unfulfilled is a game decision, not an engine
>   decision - so the engine must give the game the information to decide if
>   and how they render such options.
>
> * Speaking of render, while the dialogue state needs to be indepedent from its
>   representation, the engine should include _a_ possible representation of
>   it - textboxes and response selection.

"The sketch" is item 4, "Dialogue and better text", in
[roadmap-complexity-estimate-v0.5.0.md](../research/roadmap-complexity-estimate-v0.5.0.md).
