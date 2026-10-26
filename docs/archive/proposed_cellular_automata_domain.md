# Codex brief: 2D cellular automata domain for the logic chatbot

## 1. Goal and context

Add a **third domain** to the existing logic-based chatbot demo, alongside the object world and network world. Reuse the existing **8×8 grid, dialogue interface, Flutter frontend, Python/FastAPI session layer, and Haskell symbolic engine** wherever possible. Inspect the current code and domain specifications before changing interfaces or grammar; do not invent a parallel architecture.

This domain is a **deterministic, multicolor cellular automaton whose rules can themselves be edited through dialogue or a GUI**. Unlike the other domains, it adds:

1. **Time evolution:** advancing the world by one or more synchronous generations is a primitive operation.
2. **Editable laws:** the user changes the transition function, not merely the current board.
3. **Backward inference:** “regress three steps” means *find a possible predecessor configuration*, not undo or replay a recorded history.

The domain will appear in a **five-minute presentation**. Favor an instantly comprehensible board and a small, coherent language over extensive features. A visible, trustworthy demonstration matters more than breadth.

## 2. World model

- Board: exactly **8 columns (A–H) × 8 rows (1–8)**, as in the other domains. **A1 is bottom-left**.
- Topology: **toroidal** (both axes wrap). There are no boundary cells. For example, **A5 and H5 are adjacent**; **D1 and D8 are adjacent**.
- Every cell has exactly **one active color**. No separate “empty,” “dead,” or “alive” state.
- The active palette has **2, 3, or 4 colors**, selected from **blue, green, red, yellow**. Use labeled swatches in the GUI; internal identifiers must not depend on display order.
- Starting/default demo setup: **three colors (blue, green, red)** and the **four-neighbor** neighborhood.
- No movement of objects or network connections: the entire domain state consists of the current colored grid, the active rule set, and the relevant evolution/history metadata.

### Neighborhood options

Only two global choices:

- **4 neighbors (von Neumann):** N, E, S, W.
- **8 neighbors (Moore):** N, NE, E, SE, S, SW, W, NW.

For A1, the four neighbors are **A2, B1, A8, H1**. In eight-neighbor mode the diagonals are **B2, B8, H2, H8**. On an 8×8 board these are eight distinct cells; a cell never counts itself.

## 3. Rule language: deliberately restricted

There may be **zero or one enabled transition rule per source color**. Every rule has this single form:

> A cell of **[source color]** becomes **[target color]** if **[exactly / at least / at most] [n]** of its neighbors are **[neighbor color]**.

Parameters:

| Parameter | Allowed values |
| --- | --- |
| Number of colors | 2, 3, or 4 |
| Active colors | A subset of blue, green, red, yellow of the selected size |
| Neighborhood | 4 neighbors or 8 neighbors |
| Source color | Any active color; at most one rule for each |
| Neighbor color | Any active color |
| Comparison | Exactly / at least / at most |
| Threshold `n` | An integer from 0 to 4 or 0 to 8, depending on neighborhood |
| Target color | Any **other** active color |
| Rule enabled | Yes / no (a missing or disabled rule means no change for that source color) |

If a condition is false, the cell **keeps its color**. If no rule is enabled for its source color, the cell likewise keeps its color. The restriction to one rule per source color prevents rule priority/conflict questions. In particular, no Boolean combinations or additional clauses are permitted.

### Transition semantics

Each generation is computed **synchronously**. Evaluate each cell's source color and neighbor counts against the **same pre-step board**, then update all 64 cells at once. No in-place iteration that allows newly updated cells to influence other cells in the same generation.

A command to advance `k` steps repeatedly applies the **same active ruleset** for those `k` steps unless the user explicitly changes the rules in between. Rule changes affect **future** transitions; they do **not** reinterpret recorded past configurations.

### Palette edits

Changing the number or membership of active colors must never silently invalidate cells or rules. For the first version, prefer an atomic, clear policy:

- Adding a color preserves the board and existing valid rules.
- Removing a color is allowed only after cells using it have been reassigned and rules referring to it have been changed or removed. Show a clear explanation in the editor; do not silently remap.
- When switching from 8 to 4 neighbors, thresholds above 4 must be corrected or rejected explicitly; do not silently clamp.
- Validate all edits before committing the revised ruleset.

This can be simplified further if the existing architecture demands it, but **invalid intermediate rules must not enter the engine**.

## 4. Initial preset

Offer a one-click **three-color cyclic preset**:

- **Blue → Green** if **at least 2 green** neighbors.
- **Green → Red** if **at least 2 red** neighbors.
- **Red → Blue** if **at least 2 blue** neighbors.
- Neighborhood: **4**.

Prepare a **fixed, visually interesting initial board**, not a new random board for each demo. Test the preset beforehand to ensure that advancing three generations visibly changes the configuration. Keep a **Reset demo** action that restores the known initial board *and* known initial rules (with explicit confirmation if necessary).

The preset is an illustrative starting point, not a special case built into the engine. Changing a threshold or neighborhood should immediately influence subsequent evolution.

## 5. User operations and questions

Reuse the chatbot's existing parsing, reference resolution, result/error conventions, and state management. Implement the **narrowest natural-language fragment that works reliably**, and expose equivalent GUI actions where appropriate. Below are intended user-facing utterances, not a requirement to support arbitrary paraphrases.

### A. Edit the board

- “Make A5 red.”
- “Set D3 to green.”
- “What color is A5?”
- “How many blue cells are there?”

Cell edits change the **current configuration**, not any prior snapshot. Reject inactive target colors. A direct GUI cell click may cycle colors or bring up a compact palette; make the interaction discoverable.

### B. Advance time: a primitive operation

- “Advance one step.” / “Step.”
- “Advance three steps.”
- “What generation is this?”

Display the generation number prominently. The board should visually update on each completed command, and the command should return a concise result (e.g., generation reached, number of changed cells). Optional animation must not obscure determinism or block interaction.

### C. Edit the rules: another first-class operation

- “Include diagonal neighbors.” / “Use eight neighbors.”
- “Use four neighbors.”
- “Change the blue rule to at least three green neighbors.”
- “Blue becomes green if exactly two green neighbors.”
- “Disable the red rule.”
- “What are the current rules?”

The **GUI rule editor and dialogue commands modify the same canonical ruleset**. A change through dialogue must appear in the editor; a GUI edit must affect subsequent dialogue/engine behavior. Do not maintain two representations with separate semantics.

Changing the active palette through dialogue is **optional for the first demo**; the GUI must support it. If a requested rule is ambiguous (for example, missing a target color and no existing target can be inferred), **ask for clarification** rather than guessing.

### D. Regress time: inference, NOT undo

- “Regress one step.”
- “Regress three steps.”
- Optionally, after presenting choices: “Show another possible predecessor.” / “Choose the one with the fewest red cells.”

Given current configuration `S`, current transition function `F`, and requested positive integer `k`, find a board `P` such that **applying `F` exactly `k` times to `P` yields `S`**. That is the entire meaning of regression. It must **not** simply retrieve a previous board from saved history.

Important properties:

- `F` may be **noninvertible**. A predecessor may not exist, or there may be one or many.
- Regression applies the **current ruleset held fixed across the hypothetical `k` steps**, not a possibly changing sequence of historical rules.
- A found predecessor is a **possible past**, not necessarily the actual past.
- If multiple candidates exist, do not pretend uniqueness. Ideally present at least one verified candidate and offer “another candidate” or a simple selection criterion.
- If a candidate is found, **verify it by forward-simulating `k` steps with the authoritative engine** before presenting it.
- Do not replace the user's current configuration silently. **Preview the candidate** and offer to adopt it as a **new hypothetical branch**.
- Never label a solver timeout or incomplete search “no predecessor.” Distinguish **found**, **proven impossible**, and **not solved within the resource limit**.
- This operation must remain separate from **Undo**, **Restore previous generation**, or any historical timeline navigation. Those use actual recorded states; regression reasons about possible states.

**Implementation caution:** searching all `2^(64k)` to `4^(64k)` possibilities is not viable. Investigate a **constraint-based encoding** (SAT/SMT or similar), consistent with the existing Haskell/Python responsibilities. Keep the forward Haskell transition semantics authoritative; any external solver witness must be checked against them. Do not introduce a large dependency solely for this feature without first checking the project and measuring performance.

**Scope and performance:** target regression for `k=1` and `k=3` on the **fixed demo preset/configurations**. Measure actual runtime; a solvable demonstration case is essential. If three-step general regression cannot be made reliable in time, keep the operation honest (bounded search + explicit “not solved”), and make a robust one-step case the fallback rather than substitute an undo implementation.

### E. History and explanation (secondary)

These are useful if time allows:

- “Why did B4 change to red?” — explain the source color, triggering rule, and neighbor count from the immediately preceding recorded step, **if known**.
- “How many red cells were there three steps ago?” — read an actual saved generation, **if one exists**.
- “Restore generation 4.” — history navigation; explicitly **not regression**.

Keep **recorded evolution** distinct from **inferred hypothetical predecessors**, especially after rule edits. If history-aware queries are omitted, the architecture should still avoid conflating the two.

## 6. Flutter GUI

### Main domain view

- Reuse the 8×8 visual board and cell coordinates.
- Show **solid, easily distinguishable colored cells**. Avoid elaborate icons or animation: the changing pattern is the visual centerpiece.
- Always show the **generation counter**, **current neighbor mode (4/8)**, and a concise indication of **which palette/ruleset is active**.
- Provide conspicuous controls for **Step**, **Step ×3**, **Rules…**, and **Reset demo**; include **Regress…** if implemented. The chatbot remains available beside/below the board, according to the existing layout.
- Because the grid is a torus, a small label like **“Edges wrap”** is sufficient; no need to draw connecting edge lines.

### Rule editor: modal overlay

There is not enough permanent space for a rule editor. Open a **modal overlay** over the grid, dimming the board behind it (still recognizable). No permanently expanded sidebar.

The overlay contains:

1. **Colors:** select 2 / 3 / 4 and the active colors.
2. **Neighbors:** toggle **4 orthogonal** / **8 including diagonals**.
3. **One compact row for each active source color**, with an enabled toggle and the template:
   **[source swatch] → [target color] if [exactly / at least / at most] [n] [neighbor color] neighbors.**
4. **Apply** and **Cancel**.

Use labels along with swatches, so that the rule is readable at a glance. Ensure the overlay fits a laptop screen and scrolling is localized if needed. Applying rules should be **atomic**. Cancel discards unsaved changes. Invalid palette/threshold combinations should be explained within the editor.

### Regression result UI

Use a small result dialog/panel with a **preview of one inferred predecessor**, showing `k`, the ruleset used, and the fact that this is **one possible predecessor**. Provide **Use this configuration** and **Cancel**. If feasible, offer **Find another**. Previewing must not destroy the original board; adoption must be an explicit branch. Display **unsatisfiable** only when proven, and **search limit reached** otherwise.

## 7. State, versions, and branching

Represent at least these conceptual pieces, following existing project types and persistence:

- Current 64-cell board.
- Active palette and global neighborhood mode.
- Per-source-color optional transition rules.
- Generation counter / position in the evolution.
- Ruleset revision or version identifier.
- Optional snapshots of actual forward history (board + ruleset used for each transition).
- Optional hypothetical predecessor candidates / branch provenance.

A board edit or ruleset edit **creates a new point of departure**. The system must not quietly pretend that an earlier recorded history continues unchanged through an edited state. After adopting an inferred predecessor, mark the new branch as **hypothetical**. The generation label may be `t − k` relative to the current state, but it must **not claim to recover what actually happened**.

Prefer immutable snapshots or existing established state-transition mechanisms. Keep forward semantics pure and deterministic. Do not break undo/discourse handling in the other domains.

## 8. Implementation order and priorities

**P0 — Must work for the presentation**

1. Add the domain and its deterministic toroidal 8×8 grid semantics.
2. Implement the single-condition, per-source-color ruleset and **synchronous** stepping.
3. Add cell color editing, **Step / Step ×3**, generation counter, and the fixed three-color demo preset.
4. Add the **modal rule editor**, with validated, atomic updates to the exact same ruleset used by dialogue.
5. Add a small reliable natural-language subset for stepping, editing cells, asking cell/color counts, and changing at least one rule or neighbor mode.
6. Confirm the entire flow works in the existing Flutter → FastAPI → Haskell integration.

**P1 — High-value showcase; pursue immediately after P0**

7. Implement **real predecessor inference**, at least for a measured demo case. Start with one step; target three. Provide candidate preview, explicit adoption, and independent forward verification. Do **not** implement history-based undo under the name “regress.”

**P2 — Only if time remains**

8. Additional predecessor candidates or color-minimization constraints.
9. Explanations from logged transitions and historical count questions.
10. More flexible dialogue paraphrases, richer animations, extra presets.

Do not spend time building arbitrary logical expressions for rules, probabilistic transitions, larger neighborhoods, a general reversible-CA framework, or sophisticated timeline editing.

## 9. Acceptance tests

Cover these before treating the domain as demo-ready:

1. **Torus / 4 neighbors:** A1 has exactly A2, B1, A8, H1. A5 is adjacent to H5; D1 to D8.
2. **Torus / 8 neighbors:** A1 additionally has B2, B8, H2, H8; no duplicates and no self-neighbor.
3. **Synchronous transition:** compare outcomes computed in different cell traversal orders; they must match.
4. **Default behavior:** when no rule applies, a cell stays its color; a disabled rule never fires.
5. **Threshold edges:** 0 and the neighborhood maximum are valid; thresholds above the maximum are rejected.
6. **Palette validity:** no cell or active rule refers to a removed color; attempting to remove an in-use color is handled explicitly.
7. **GUI/dialogue consistency:** changing a threshold through chat updates the editor; changing it in the editor changes the next step's engine result.
8. **Rule versioning:** editing a rule affects subsequent steps, not previously stored actual generations.
9. **Regression witness:** for a board produced from a known starting board by `k` forward steps, the regression solver returns a `P` (not necessarily the original) for which independent `F^k(P)` exactly equals the target.
10. **Regression is not undo:** with no saved earlier state, predecessor inference still attempts to solve the constraints. With multiple valid predecessors, never claim to have identified the actual one.
11. **Unsatisfiable vs. timeout:** only an actual proof of impossibility produces “no predecessor”; resource exhaustion produces a separate status.
12. **Isolation:** existing object/network domains and their sessions continue working.

A simple **impossible-predecessor test** is available within the permitted schema: in a two-color world, configure **blue → red if at least 0 red neighbors**, with **no rule for red**. Every one-step result is entirely red, so any target board containing blue has **no one-step predecessor**. This tests genuine impossibility, not mere failure to find a witness.

## 10. Suggested five-minute presentation sequence

Keep the board large and the rule editor hidden until needed.

1. **Introduce the toroidal three-color board** and show a few rules in plain language.
2. Ask the chatbot to **“Advance three steps.”** Show the deterministic evolution and updated generation counter.
3. Open **Rules…** as an overlay and **change one threshold or switch from 4 to 8 neighbors**. Apply; step again. Point out that the **laws**, not just the data, have changed.
4. Show a matching **dialogue-based rule change**, reopen the overlay briefly to demonstrate that GUI and dialogue share the same formal representation.
5. If verified and fast enough, run **“Regress three steps”** on a prepared solvable configuration. Present a **possible predecessor**, verify forward evolution, and explicitly contrast this with undo. Otherwise demonstrate an honestly supported one-step regression, with three-step search as a visible experimental feature.

**Presentation point:** the chatbot can maintain a formal world, execute deterministic changes, modify its transition laws, and reason backward about possible causes. Its answers can be verified, rather than merely trusted.

## 11. Deliverables and working discipline

- A new domain integrated into the existing app, not a separate standalone toy.
- Clear, narrow language specification/documentation for the supported utterances and error responses.
- Modal Flutter rules editor sharing one validated ruleset with chatbot operations.
- Unit/integration tests for topology, rule semantics, stepping, and (if delivered) predecessor inference.
- A reproducible demo preset and an end-to-end demonstration path.
- A brief implementation note stating **which features are complete**, whether **regression is a genuine constraint search**, which step counts are reliably supported, and any measured timeout/performance limits.

When a feature is too expensive or unsupported, **surface the limitation**; never simulate symbolic inference by pretending that history lookup is regression. Avoid unrelated refactoring under presentation deadlines.
