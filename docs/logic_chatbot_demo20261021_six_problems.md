# Six problems with an LLM-only approach

Each item pairs evidence for the problem with a separate paper supporting the corresponding design choice in a symbolic–probabilistic chatbot; partial or conditional support is stated explicitly.

1. **Defaulting on unconfirmed assumptions**

   - **Problem evidence — Laban et al. (2026), [LLMs Get Lost In Multi-Turn Conversation](https://proceedings.iclr.cc/paper_files/paper/2026/hash/59f6421e64707225fdf5b28840679a07-Abstract-Conference.html).** Models frequently made premature assumptions when requirements emerged gradually across dialogue turns and failed to revise the resulting solutions as further information arrived.
   - **Support for the approach — Saparina & Lapata (2025), [Disambiguate First, Parse Later: Generating Interpretations for Ambiguity Resolution in Semantic Parsing](https://aclanthology.org/2025.findings-acl.863/).** Generating explicit alternative interpretations before formal parsing improved coverage of valid readings across datasets, supporting an interpretation stage that exposes alternatives before commitment, although interactive clarification was not evaluated.

2. **Losing established requirements across turns**

   - **Problem evidence — He et al. (2024), [Multi-IF: Benchmarking LLMs on Multi-Turn and Multilingual Instructions Following](https://arxiv.org/abs/2410.15553).** In three-turn tests, models violated instructions they had previously obeyed as compatible requirements accumulated, even though the full preceding conversation remained available in their input.
   - **Support for the approach — Maraev et al. (2025), [Combining Information State Update, Harel Statecharts and LLMs for controllable and flexible Conversational AI](https://aclanthology.org/2025.clasp-main.3/).** A working hybrid dialogue system demonstrated explicit storage of commitments and unresolved questions under rule-governed state updates, providing an architectural precedent for persistent dialogue state, although prevention of requirement loss was not empirically tested.

3. **Unreliable multistep reasoning**

   - **Problem evidence — Wu et al. (2026), [LogicGraph: Benchmarking Multi-Path Logical Reasoning via Neuro-Symbolic Generation and Verification](https://arxiv.org/abs/2602.21044).** The tested LLMs generally became less reliable at producing logically valid proofs as the number of required reasoning steps increased.
   - **Support for the approach — Hubert et al. (2026), [Olympiad-level formal mathematical reasoning with reinforcement learning](https://doi.org/10.1038/s41586-025-09833-y).** Learned search over symbolic proof states produced formally verified solutions to three IMO 2024 problems, including the competition’s hardest problem.

4. **Persistent risk of hallucination**

   - **Problem evidence — Xu, Jain & Kankanhalli (2024), [Hallucination is Inevitable: An Innate Limitation of Large Language Models](https://arxiv.org/abs/2401.11817).** No computable learning procedure based on examples can guarantee an error-free LLM for every computable task, so increasing training data alone cannot provide universal freedom from errors.
   - **Support for the approach — Ryu et al. (2025), [Divide and Translate: Compositional First-Order Logic Translation and Verification for Complex Logical Reasoning](https://proceedings.iclr.cc/paper_files/paper/2025/hash/3e592c571de69a43d7a870ea89c7e33a-Abstract-Conference.html).** Compositional formalization with symbolic verification substantially reduced translation errors and improved answer accuracy across seven reasoning benchmarks, supporting the separation of interpretation from inference without establishing elimination of factual hallucinations.

5. **Unfaithful explanations of reasoning**

   - **Problem evidence — Chen et al. (2025), [Reasoning Models Don’t Always Say What They Think](https://arxiv.org/abs/2505.05410).** Tested reasoning models often omitted hints that demonstrably changed their answers, showing that generated reasoning explanations need not faithfully reveal the factors behind a decision.
   - **Support for the approach — Sadeddine & Suchanek (2025), [Verifying the Steps of Deductive Reasoning Chains](https://aclanthology.org/2025.findings-acl.25/).** Combining symbolic deduction with neural entailment checks achieved competitive verification performance while exposing premise provenance and deduction trees, supporting inspectable justifications, although language-processing errors prevented complete certification of reasoning chains.

6. **Threat of model collapse**

   - **Problem evidence — Dohmatob et al. (2025), [Strong Model Collapse](https://proceedings.iclr.cc/paper_files/paper/2025/hash/284afdc2309f9667d2d4fb9290235b0c-Abstract-Conference.html).** In the studied regimes, even a small persistent fraction of imperfect synthetic training data created an error floor that adding more training data did not remove.
   - **Support for the approach — Yi et al. (2026), [Escaping Model Collapse via Synthetic Data Verification: Near-term Improvements and Long-term Convergence](https://proceedings.iclr.cc/paper_files/paper/2026/hash/29806b2e4dcb35e42abed21d43e2b7d8-Abstract-Conference.html).** External verification enabled improvements during synthetic retraining under suitable conditions, while the theoretical long-run limit depended on verifier bias, supporting independent validation of generated training data.

*Years follow the cited publication where available: Laban is ICLR 2026; Hubert is Nature 2026, first published online in 2025; Dohmatob is ICLR 2025; Xu first appeared in 2024 and was revised in 2025.*

