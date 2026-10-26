> Archived pre-v2 language. Current contract: [Network v2](../network-language-v2.md).

# Network domain: ontology and core language

The Haskell domain identifier is `network`. The JSON bridge and FastAPI support this domain using generic attributes and
its seven-object initial world. Flutter supports domain switching and a network editor with all 16 port patterns.
See the [JSON contract](../json-contract.md).

## Ontology

An object has an identifier, optional board position, optional color, and four
independent unary port attributes. The board is 8×8, A1–H8. An empty square has
no object; an object without ports is an isolated node.

| Attribute | Values / descriptors | Aliases |
|---|---|---|
| color | red, blue, green, yellow | — |
| north | north (present), absent otherwise | up |
| east | east (present), absent otherwise | right |
| south | south (present), absent otherwise | down |
| west | west (present), absent otherwise | left |

Color belongs to the entire object. There are no size or shape attributes.
Ports can face an empty neighbor or the board boundary. No connectedness
algorithm or restriction on dangling ports is introduced in this stage.

## Core and reference language

`A4 north.` creates an object if needed and adds its north port; other ports
and color are preserved. `A4 remove north.` removes only that port. Aliases
normalize to their compass names, including in removal and descriptions.
`A4 north?` and `Is A4 up?` are Boolean checks. Missing ports are false, not
unknown. Empty-square questions report failure to resolve an object, as in the
objects domain. `color of A4?` returns the color or `none`.

Layer 2 descriptions need no new syntax:

- `A red north east on A4.` creates a red object with two ports.
- `The north east is blue.` resolves a compatible object and changes its color.
- `It south.` adds its south port.
- `Is the blue north east south?` checks its south port.

Descriptions select objects that have the stated properties; unspecified ports
are unrestricted. Existing salience and clarification rules apply. Identifiers,
squares, movement to a square, swap, unplacement, deletion, and attribute removal
retain their existing meanings. Questions require `?`; performatives use `.`
except at the end of an entry.

A unary word after a subject is a Boolean check rather than a shorthand value
query. Explicit generic forms such as `north of A4?` remain accepted by the
shared grammar, but are unnecessary; use `A4 north?`.

## Square occupancy questions

The shared core also accepts `Is the square A4 occupied?` and
`Is square A4 taken?`. Both return true if any object occupies A4, including a
dot, and false when the square is unoccupied. They add no object reference or
salience mention. The `square` keyword and question mark are required.
`empty` retains its no-port node meaning; it is not a vacancy-check alias.

## Modules and GHCi

`Domains.Network.Definition` declares the ontology; `Domains.Network.Library`
assembles it without Layer 3 callbacks. `Domains.Network.Sandbox.networkWorld`
is a fixed seven-object sample with varied colors, port combinations, and
positions. It is stable across runs and does not replace the API's initial world.

From `backend/logic_engine`, run `cabal repl`, then:

```haskell
import Domains.Network.Library
import Domains.Network.Sandbox
import Domains.Network.Definition
import Layer2Parser
import Layer2Evaluation
import Domain
import Pretty
putStrLn (prettyWorldIn networkDomain networkWorld)
either putStrLn (\sentences -> let (w, _, _, feedback) = evaluateEntryIn networkLibrary networkWorld [] sentences in putStrLn feedback >> putStrLn (prettyWorldIn networkDomain w)) networkIntroduction
```

Run `cabal test network-tests` for the network core checks.
