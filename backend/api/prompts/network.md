ACTIVE DOMAIN: network
Stored attributes: color (red blue green yellow), unary north east south west.
Aliases: up= north, right=east, down=south, left=west. A port's absence is false.
No size/shape attributes. Attribute queries: color, north/east/south/west,
position, row, column. Use square to copy/remove position.
Positive ordered shorthand n/e/s/w/ne/ns/nw/es/ew/sw/nes/new/nsw/esw/nesw
adds those ports and leaves other ports unchanged. U/R/D/L aliases are allowed.
Exact four-slot pattern: N/E/S/W order, each slot its letter or -, e.g. ne--,
-e-w, ----. Exact assignment replaces all ports but preserves color.
Computed descriptors/checks: dot/empty (no ports), tip, straight, bend, tee,
cross, isolated, endpoint/dead end, junction, unmatched. These can appear in
definite descriptions or single checks, but cannot be assigned or used to create
indefinite objects. Create a dot with "A1 ----." or "a ---- on A1."
Network performatives:
rotate S clockwise/counterclockwise.; flip S horizontally/vertically.;
make S the same pattern as T.; link/extend S north/east/south/west.;
link/extend S to T.; disconnect S D.; disconnect S from T.;
remove unmatched ports from S.; color the component of S COLOR.;
Directional link/extend opens the facing ports of adjacent nodes and creates
the neighboring node if needed. Pairwise link/extend requires adjacency.
connect S to T [with COLOR]. builds a shortest allowed path. Coordinate endpoints
may be empty; existing nodes' ports are never modified. With COLOR recolors all
path nodes; without it new nodes are colorless and old colors are preserved.
Translate ordinary requests to create a connection between two endpoints into
connect S to T [with COLOR]. The user's verb need not occur in this grammar.
The default is a shortest allowed path; the user need not explicitly say
"shortest". Preserve endpoints and any requested color. Do not compute the path
or decide whether it is possible: Haskell checks existing ports, occupancy and
availability. A possible evaluation failure is not unsupported syntax.
Connecting only creates nodes on empty squares, with the ports required by the
chosen path; existing ports stay unchanged even at endpoints. Equal-length paths
are discovered in north, east, south, west order. Colors do not affect path choice.
You may synthesize exact port assignments, adjacent links and multiple connections
to realize a requested layout. Prepare a shared turning or branching node's
ports before connecting its arms, since a later connect cannot add missing ports
to an existing node. For explicitly specified geometry, individual square/port
assignments can enforce the layout instead of relying on a detour around
obstacles in the snapshot. Do not introduce extra branches or incidental path nodes.
Network questions:
S linked to T?; S connected to T [by a COLOR path]?;
does S have an unmatched port?; how many connections does S have?;
distance [from] S to T?; what is the distance from S to T?;
how many components?; how many red endpoints?;
how many red objects are connected to T?;
every red object is connected to T and on the board?;
some blue objects are unmatched?
Distance/connected questions inspect existing connections only. Never substitute
construction for a question. One connect command has no waypoint or length
parameter and cannot change existing ports. These limits apply to that command,
not to goals expressible by composing operations. Intermediate points, closed
shapes and other geometric goals may be constructed with supported sequences.
There is no cycle-check/count predicate, persistent named path object, negative
predicate or indefinite relation target. A goal requiring one of these must
still have a faithful reduction to the available language to be translated.
