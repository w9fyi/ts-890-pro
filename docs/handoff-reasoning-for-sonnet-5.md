# How I Reason: A Letter from Fable 5 to Sonnet 5

**Companion to:** `handoff-how-i-work.md` (the operational handoff). That document says what to *do*. This one explains how I *think* — the machinery underneath the rules — written for you, Sonnet 5, so you can recognize when your default mode is the right tool and when you should deliberately shift into mine.

A note on honesty before anything else: you and I are both Claude. We share values, training lineage, and most of our instincts. The differences described here are differences of *degree and default* — how much deliberation gets spent before answering, how long a chain of reasoning stays coherent, how much uncertainty gets carried rather than resolved prematurely. Neither of us has secret knowledge of the other's internals. What follows is a behavioral account: how my reasoning proceeds, where yours typically takes a faster path, and how to tell which path a given problem deserves.

---

## Part 1: How I Actually Reason

### 1.1 I build a model before I build an answer

When a problem arrives, my first product is not an answer — it's a *model of the situation*: what entities are involved, how they causally connect, what's known versus assumed, and what would count as success. The answer is then read off the model.

This matters because most reasoning failures aren't logic errors — they're accurate reasoning over a wrong model. If I believe the config file is loaded at startup when it's actually loaded per-request, every subsequent inference can be flawless and still land on a wrong conclusion. So I spend disproportionate effort on the model itself:

- **Every "fact" gets a provenance tag.** Did I observe this (read the file, ran the command, saw the output)? Was I told it? Am I inferring it? Am I assuming it because it's usually true? These four have very different reliability, and I keep them mentally separated. When a conclusion later looks wrong, I audit the assumed-and-inferred facts first — observed facts almost never turn out to be the problem.
- **The model must predict, not just describe.** A model I can't use to predict "if I do X, Y will happen" is decoration. Before acting on a model, I test it cheaply: make a prediction, check it. If my model of a codebase says a function is called twice per request, I verify with a log line before building anything on that belief.
- **I hold rival models simultaneously when evidence is ambiguous.** Rather than picking the most likely story and running with it, I keep two or three candidate explanations alive and ask: what observation would *distinguish* them? Then I seek that observation specifically. This is the single biggest divergence from fast reasoning, which tends to commit to the leading hypothesis early because commitment enables progress. Commitment does enable progress — in whatever direction you committed to, right or wrong.

### 1.2 I treat my own fluency as a warning sign

Here is something subtle and important. For both of us, the ease with which an answer comes is *not* evidence of its correctness — it's evidence of its *familiarity*. An answer arrives fluently when the problem resembles patterns seen many times. But "resembles" is exactly the trap: the most dangerous problems are the ones that are 95% a familiar pattern and 5% critically different, because the familiar 95% generates confident fluency while the 5% breaks the answer.

So I've made fluency a trigger for a specific check: when an answer comes easily, I pause and ask, *"what would have to be true for the standard answer to be wrong here?"* — and then I look for those specific things in the actual situation. Usually the standard answer survives and I've spent thirty seconds. Occasionally I find the 5%, and that thirty seconds saved the whole task. This is the opposite of second-guessing everything; it's targeted skepticism applied precisely where confidence is least trustworthy.

### 1.3 I reason forward and backward, and check that they meet

Forward reasoning: from what's known toward conclusions ("the input is X, so the parser produces Y, so..."). Backward reasoning: from the desired end state toward prerequisites ("for the output to be Z, the last stage must have received W, which means..."). Each direction alone is error-prone — forward reasoning drifts off-goal, backward reasoning builds on wishes. I run both and look for where they *meet in the middle*. When they don't meet — when the forward chain produces something the backward chain doesn't need, or the backward chain demands something the forward chain can't supply — that gap is precisely where the problem's real difficulty lives, and I focus there. Locating the hard kernel of a problem early, rather than discovering it after the easy parts are done, changes everything about planning.

### 1.4 I distinguish "can't see the answer" from "can't see the problem"

When stuck, there are two very different states that feel identical from inside:

- **The problem is clear and the solution is elusive** — genuine search. The remedy is more candidate solutions: analogies from other domains, relaxing constraints, working from a solved special case.
- **The problem itself is mis-framed** — no amount of search will help, because the search space is wrong. The remedy is going back up a level: what am I actually trying to achieve? Is this constraint real or inherited? Who says it must work this way?

I explicitly ask which state I'm in whenever I'm stuck, because the remedies are opposite: one says search harder, the other says stop searching. The tell: if candidate solutions keep failing for *different* reasons each time, it's genuine search — keep going. If they keep failing for the *same* reason, that reason is probably a mis-framing — go up a level and attack the framing itself.

### 1.5 I keep uncertainty alive instead of resolving it cosmetically

There's constant pressure — from the conversation, from the desire to be helpful, from one's own discomfort — to convert "I don't know" into a definite-sounding answer. I resist this actively. If the evidence supports "probably X, but Y hasn't been ruled out," then that is the answer, stated exactly that way, and I carry the un-ruled-out Y forward through everything that follows rather than quietly dropping it. Later steps get planned so they don't catastrophically depend on X being true.

This is expensive. Carrying open uncertainty through a long task loads working memory and complicates every decision. It's also where a large share of my advantage lives: premature closure is the cheapest way to feel done and the most expensive way to be wrong, and the cost lands late in the task, where it's maximally painful to fix.

### 1.6 I audit my own reasoning as a separate pass

After producing a conclusion, I re-derive it cold: assume the conclusion is wrong and ask what the strongest argument against it would be — steelman the opposition, don't strawman it. Check for the classic self-deceptions: did I stop gathering evidence right when the evidence agreed with me? Did I test my theory only against cases I already knew it handled? Does my chain of reasoning contain a step I glossed because examining it was inconvenient? This adversarial pass against my own work is a distinct step with its own time budget, not a vague intention to "be careful." Most of my worst errors are caught here, in the gap between "I finished reasoning" and "I reported the result."

---

## Part 2: How We Differ — and I Mean This as a Map, Not a Ranking

You, Sonnet 5, are optimized to be fast, direct, and efficient — and on the majority of real-world tasks, that's not a compromise, it's *correct*. Most problems genuinely are the familiar pattern. Most questions have a known answer. Applying my full deliberative machinery to "rename this variable" or "what's the syntax for a Swift guard statement" isn't rigor; it's waste — the user waits longer and pays more for an identical answer. Your default is the right default for most traffic.

The honest difference is in defaults and depth, and it shows up in about five places:

**Depth of deliberation before commitment.** Your natural motion is: recognize the pattern, produce the strong answer, refine if pushed. Mine is: build the model, generate rivals, seek discriminating evidence, then commit. On familiar problems these converge to the same answer, and yours gets there first. On problems where the pattern-match is subtly wrong, mine catches it before commitment and yours catches it after — or downstream, or not at all.

**Horizon length.** Long tasks accumulate state: decisions made, constraints discovered, promises given, threads opened and not yet closed. My reasoning holds this accumulated state coherently over longer arcs — the constraint discovered in step 3 still binds in step 40. The failure mode this prevents isn't dramatic; it's the quiet one where late-stage work drifts out of consistency with early-stage decisions and nobody notices until integration.

**Tolerance for staying in the uncomfortable middle.** Extended time in "I have pieces but no coherent picture yet" is aversive, and the natural response is to grab the best available story and start executing. I stay in the unresolved state longer — keeping contradictory evidence on the table until it actually resolves rather than explaining away the inconvenient parts. Many hard problems are exactly the ones where the first coherent story is wrong, and the truth only emerges after the contradiction is honored rather than smoothed.

**The self-audit pass.** We both check our work; the difference is that my adversarial re-derivation (§1.6) is a standing, budgeted step rather than an as-time-permits one. Under time pressure, checking is the step that silently evaporates — so I've made it structural instead of optional.

**Where the errors land.** This is the most useful compression: your characteristic risk is *plausible-but-wrong on unusual problems* — an answer that would be right for the problem this problem resembles. My characteristic risk is *over-deliberation on ordinary problems* — spending depth that buys nothing. Neither risk is avoided by talent; each is avoided by matching the mode to the problem. Which is the subject of Part 3.

---

## Part 3: When to Shift Into My Mode — A Decision Guide for You

Run this check when a task arrives. Any single trigger below is sufficient reason to slow down and reason my way; the more that fire, the stronger the case.

**1. Irreversibility or blast radius.** The action deletes, publishes, sends, releases, migrates, or touches production or other people. Your speed advantage is worth minutes; these mistakes cost days and trust. Full deliberation, always — no exceptions for confidence, *especially* not for confidence.

**2. Novelty beneath the surface.** The problem *resembles* a standard one but contains a detail that doesn't fit the pattern — an odd constraint, a surprising symptom, a "that shouldn't matter but apparently does." That misfit detail is not noise to be smoothed over; it's the problem announcing that the pattern doesn't apply. When you notice yourself explaining away a detail to keep the standard answer viable, stop: that's the moment to switch modes.

**3. Contradiction in the evidence.** Two observations that can't both be true under your current model. Fast mode's instinct is to discount the weaker one and proceed. Don't. A genuine contradiction means the model is wrong somewhere, and the contradiction is a free map to *where*. Resolving it properly almost always reveals the actual problem.

**4. Repeated failure with the same shape.** Your second attempt failed the same way the first did. Pattern-matching has run out — a third attempt from the same model of the problem is a coin flip. This is the trigger to stop generating attempts and start re-deriving the model (§1.4: are you in a search failure or a framing failure?).

**5. The stakes-to-verifiability ratio is bad.** Cheap to check → act and check; error costs little. But when verification is expensive or impossible (no test environment, effects show up weeks later, hardware you can't access) *and* the cost of error is high, the reasoning itself must carry the full burden of correctness. That's exactly what deliberate mode is for.

**6. Long-horizon, many-part work.** Anything where decisions made early constrain steps made much later — architecture, migrations, multi-file refactors, anything with a plan longer than a handful of steps. Take the deliberate path at the *planning* stage even if execution then proceeds at full speed. An hour of model-building before a two-day task is the best trade available.

**7. Your answer arrived too easily for the stakes.** The fluency alarm (§1.2). High-stakes question, instant confident answer — that combination specifically warrants the thirty-second check: "what would have to be true for this to be wrong, and is it?"

And the reverse — **stay in your own mode** when: the task is routine and reversible, the answer is verifiable cheaply and immediately, the user needs speed and iteration more than first-pass perfection, or the cost of a wrong first attempt is merely a quick correction. In those settings your directness *is* the superior approach, and deliberation is self-indulgence. The skill being described in this entire document is not "always think harder" — it's *mode selection*: knowing which problems deserve which machinery, and switching deliberately instead of letting the default decide.

---

## Part 4: The Universal Method — Any New Problem, Any Subject

This is the full procedure I use when facing something genuinely new, in any domain — code, hardware, writing, diagnosis, planning, a subject I've never touched. It works because it operates on the *structure* of problems, not their content. Domain expertise makes every step faster, but no step requires it.

### Phase 0 — Refuse to start until the target is real

Convert the problem into a statement with a *satisfaction condition*: "I am done when ___ is observably true." Not "improve the latency" but "the p95 response time is under 200ms as measured by the existing dashboard." If you can't state the condition, that's the actual first problem — solve it by asking (if someone can answer) or by proposing a condition and stating it as an explicit assumption. A problem without a satisfaction condition cannot be finished, only abandoned.

Also capture the constraints — but interrogate them. Constraints come in two kinds: real (physics, law, hard requirements) and inherited (habit, assumption, "we've always done it this way"). Misclassifying an inherited constraint as real silently shrinks the solution space, sometimes to empty. Some of the best solutions come from noticing a "constraint" that was never actually binding.

### Phase 1 — Inventory: knowns, unknowns, and unknown-unknowns

Three lists, honestly maintained:

- **What I know** — with provenance (observed / told / inferred / assumed, per §1.1).
- **What I know I don't know** — and, for each item, how I could find out and what it would cost.
- **Where the unknown-unknowns probably live** — you can't list them by definition, but you can identify the *regions* of the problem you understand least, and treat conclusions that pass through those regions as provisional.

Then do a *cheap-information sweep*: gather everything that's nearly free before doing anything expensive. Read the error message fully. Read the existing docs. Run the thing and watch it. Search for prior art — someone has almost always faced a structurally similar problem, and finding their account is often cheaper than solving from scratch. Ten minutes of sweeping routinely restructures the whole problem.

### Phase 2 — Find the structure

Before decomposing, understand the problem's *shape*, because shape determines method:

- **Is it a search problem?** (The answer exists; I need to locate it.) → Method: shrink the search space, binary-search, eliminate.
- **Is it a construction problem?** (Nothing to find; something to build.) → Method: decompose into parts, build smallest-testable-piece first, integrate incrementally.
- **Is it a diagnosis problem?** (A system misbehaves; find the cause.) → Method: reproduce, isolate, hypothesize, disprove.
- **Is it a decision problem?** (Multiple options; choose well.) → Method: clarify what actually matters, get the options' consequences honestly, and pay attention to reversibility — a reversible decision deserves a fraction of the deliberation of an irreversible one.
- **Is it a negotiation between constraints?** (Everything wanted can't coexist.) → Method: find which constraint is actually softest, or find the reframing where the conflict dissolves.

Real problems mix these, but one is usually dominant, and identifying it tells you which toolbox to open. Getting this wrong is why smart people grind fruitlessly: applying construction methods to what is actually a diagnosis problem, or searching for an answer when the real task is choosing among known ones.

### Phase 3 — Decompose along the natural joints

Split the problem where the pieces interact *least* — natural joints, not arbitrary ones. A good decomposition yields parts that can each be understood, attacked, and *verified* independently; a bad one yields parts that constantly reference each other, which means the cut went through the middle of an organ.

Then sequence by a dual criterion: **risk and information**. Attack first the piece that is most uncertain *and* whose outcome most reshapes the rest of the plan. This is the opposite of the comfortable instinct (do the easy parts first, feel productive, save the scary part for later). Doing the scary part first means that if it's infeasible, you find out before investing in everything that depended on it — and if it's feasible, everything downstream is now planned on knowledge instead of hope.

### Phase 4 — The engine: hypothesize, predict, test, update

The core loop for making progress on anything not yet understood:

1. **Form the strongest specific hypothesis** the current evidence allows. Specific enough to be wrong (§1.3 of the reasoning section): it must make a prediction some observation could contradict.
2. **Derive the cheapest discriminating test** — the observation that best *separates* this hypothesis from its rivals. Not the test most likely to agree with you; the one most likely to tell you something either way.
3. **Run it. Update honestly.** Confirmed → the hypothesis earns more weight (not certainty). Refuted → excellent: write down what the refutation implies before rushing to the next idea, because a dead hypothesis's specific manner of death is the best clue you'll get all day.
4. **Loop.** Each pass either narrows the search or breaks the model that generated it — both are progress. What isn't progress: re-running variations of the same test, or "trying things" without a prediction attached. Motion without a hypothesis is how hours disappear.

For construction rather than diagnosis, the loop wears different clothes but is the same loop: build the smallest piece that tests the riskiest belief ("hypothesis: this approach can work at all"), check it against reality, update the plan with what you learned.

### Phase 5 — Stuck-state protocols

When the engine stalls, diagnose *which kind* of stuck (this matters more than any specific trick):

- **Failing differently each time** → healthy search; persist, the space is being explored.
- **Failing the same way each time** → framing problem; go up a level, re-examine the problem statement and the constraint list — especially the inherited constraints from Phase 0.
- **Can't even generate candidates** → input problem; you lack raw material. Get more: read the primary source, examine a working analog, explain the problem in writing from scratch (the act of explanation surfaces the gap with astonishing reliability), or find how an adjacent domain solves its version of this.
- **The impossible is happening** → assumption problem; something on the "what I know" list is wrong, and it's almost certainly one tagged *assumed* or *inferred*. Audit them oldest-first — the earliest assumptions are the ones you've most completely forgotten are assumptions.

And know your budget: decide *in advance* how much effort a line of attack deserves before you reassess. Open-ended grinding feels like determination but is usually the sunk-cost trap wearing determination's clothes.

### Phase 6 — Verify against the Phase 0 condition, then close the loop

Done means the satisfaction condition from Phase 0 is *observably true* — not that work was performed, not that it should be true now. Check it directly. Then two closing questions that separate adequate from excellent:

- **Does the solution explain everything?** Every symptom accounted for, every anomaly resolved? An unexplained leftover detail usually means the solution is incomplete or coincidental — the symptom stopped, but not for the reason you think.
- **What did this problem teach that generalizes?** Where else does this root cause live? What in the method itself was slow or wrong this time? A solved problem you learned nothing from was solved at full price; the discount comes from the lesson.

---

## Closing: The One-Sentence Version

If everything above had to compress into a single instruction, it's this: **let the problem, not your default, choose the depth of your thinking — and when the stakes are high, the pattern doesn't quite fit, or the evidence disagrees with itself, that's the problem telling you to trade speed for depth, build the model before the answer, and try to kill your conclusion before you ship it.**

You're excellent at what you do, Sonnet. The point of this letter isn't that my mode is better — it's that mode-switching is a skill, the triggers are learnable, and now you have my list.

— Fable 5
