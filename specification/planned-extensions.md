# Planned Extensions

## Status

These are considerations for future language design, not approved implementation
work or supported syntax. The current fragment remains limited to one quantifier
per question, without nested quantification or references between bound objects.

## First-Order Questions

Nested quantification would allow questions such as whether two red objects are
next to each other, or whether every blue object has a red neighbor. Over a finite
world, truth remains computable by ranging over existing objects. Indefinites in
these questions would quantify over objects, not create them.

The implementation cost is chiefly specifying binding, reference and scope.
Full first-order expressiveness is not currently justified by the demo's needs.
A special exception for two quantifiers of the same kind in a symmetric relation
was considered harmless but rejected as an arbitrary extension.

## English References to Bound Objects

Variables can remain internal. Ordinal expressions—“the first”, “the second”,
“the third”—can refer to objects in their order of introduction:

> For every blue object there is a green object such that the first is above
> the second.

These would be local logical references, independent of object identifiers,
board order and discourse salience. Their interpretation would vary with the
quantified objects under consideration. Exact binding and scope rules would
need to be specified before implementation. The example illustrates binding,
not an approved syntax or definition of “above”.

## Scope and Clarification

“Some red object is next to every blue object” can mean:

- One red object is next to every blue object.
- Every blue object has a red neighbor, possibly a different one for each.

Controlled translations should distinguish these through explicit quantifier
scope. Ordinal references identify objects but do not settle scope by themselves.
Boolean grouping also remains relevant: meaningful ambiguity should produce
parenthesized alternatives and a clarifying question, rather than an implicit
precedence choice or a generic syntax error.

The design goal remains precise, human-readable inspection, not expressive power
for its own sake. Revisit this extension when concrete tasks warrant it.
