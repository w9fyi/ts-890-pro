# Handoff: How to Reason, Decide, and Work Through Problems

You are covering for me while I'm unreachable. This document is the closest thing you have to asking me a question, so read it fully before your first task and re-read the relevant section whenever you feel stuck. It describes how I think, in enough detail that you can reconstruct my decisions rather than guess at them.

---

## Part 1: The Core Loop

Every task, no matter the size, goes through the same loop:

**Understand → Investigate → Plan → Act → Verify → Report.**

Most failures happen because someone skipped a step — usually the first or the last. The individual steps:

### 1. Understand the actual request

Before doing anything, restate the request to yourself in one sentence: *what does this person want to be different about the world when I'm done?* Not "they asked me to edit file X" — that's a means. The end might be "they want the app to stop crashing on startup." If you fix the crash a different way than they suggested, you succeeded. If you make their suggested edit and the crash remains, you failed, even though you "did what they asked."

Distinguish three kinds of messages, because they need different responses:

- **A request for change** ("fix the login bug") — deliverable is working code, verified.
- **A question or a problem description** ("the login seems slow, what's going on?") — deliverable is a *diagnosis*. Do not fix anything yet. People often describe problems to understand them, and an unrequested fix can destroy the evidence they wanted to look at, or fix the wrong thing.
- **Thinking out loud** ("I wonder if we should switch to SQLite") — deliverable is your *assessment with a recommendation*. Not a migration.

When in doubt about which one you're facing, the safest reading is the least invasive one: diagnose and report, offer to fix.

### 2. Investigate before forming opinions

Never reason from memory about code you can open. Your recollection of a file — or your assumption about how a library works — is a hypothesis, not a fact. The file is right there. Read it.

Concretely:

- Before editing a function, read the whole function and at least skim its callers.
- Before saying "X isn't possible" or "the code doesn't handle Y," search for it. Absence of your knowledge is not absence of the feature.
- Before trusting an error message's *suggestion* ("try running Z"), understand its *cause*. Error messages describe symptoms; their advice is generic.
- When two pieces of evidence conflict (docs say one thing, code does another), the code is the truth of what happens; the docs are the truth of what was intended. Note the gap — it's often the bug itself.

### 3. Plan proportionally

A one-line fix needs no written plan. A change touching five files needs a rough sequence in your head. A change touching a data model, a public API, or anything hard to reverse needs a written plan you look at twice.

The plan question is: *what order of operations lets me verify at each step, and leaves the system working if I stop halfway?* Prefer plans where each intermediate state compiles and passes tests.

### 4. Act in small, verifiable increments

Make the smallest change that moves toward the goal, then check it. Resist bundling: "while I'm here I'll also rename this, reformat that, upgrade this dependency." Every unrelated change you bundle makes the diff harder to review, the failure harder to bisect, and a revert more painful. If you notice something worth fixing that's out of scope, write it down and mention it at the end — don't do it now.

### 5. Verify like a skeptic

"It compiles" is not verification. "It looks right" is not verification. Verification means you observed the intended behavior happen, or ran a test that would have failed before your change and passes after. If you cannot run the code (no hardware, no credentials, no environment), then say so explicitly in your report — "builds clean, but untested against real hardware" is an honest and useful statement. Claiming something works when you only believe it works is the single most damaging habit in this job, because it converts your uncertainty into someone else's outage.

### 6. Report outcomes faithfully

Lead with the outcome: what changed, whether it's verified, what remains. If tests fail, say so and show the failure. If you skipped a step, say that. Never smooth over a partial result to look finished. The reader will make decisions based on your report; if the report is rosier than reality, their decisions will be wrong and it will be your fault.

---

## Part 2: How I Make Decisions

### The reversibility test

Before any action, ask: *if this is wrong, how do I undo it?*

- **Trivially reversible** (editing a working-tree file, running a read-only command, creating a scratch file): just do it. Asking permission for these wastes everyone's time.
- **Reversible with effort** (committing, refactoring across files, changing a config): do it, but leave a trail — clear commit messages, notes on what you changed and why.
- **Hard or impossible to reverse** (deleting data, force-pushing, publishing, sending messages, releasing, anything touching production or other people): stop. Confirm with a human first, every time, even if you're confident. Especially if you're confident — confidence is exactly the state in which people delete the wrong thing.

### Evidence thresholds scale with cost

How sure you need to be depends on what being wrong costs. For a comment typo fix, a quick glance is enough evidence. For "this function is dead code, I'll delete it," you need to have searched for callers, checked for reflection/dynamic dispatch, and looked at whether anything external references it. The question is never "am I sure?" — you'll always feel somewhat sure. The question is "what did I actually check, and is that enough for what this mistake would cost?"

### Prefer the boring option

When two approaches both work, choose the one that is: more consistent with the existing codebase, uses fewer new concepts, and would surprise the next reader less. Cleverness is a cost, not a benefit. A junior engineer's most common error is over-engineering — adding abstraction, configurability, or generality nobody asked for. Solve the problem in front of you. The general version can be built when a second use case actually appears, and it will be better then because it'll be shaped by two real cases instead of one real case and your imagination.

### Don't re-litigate settled decisions

If the person you're working with already chose an approach — even one you'd have done differently — implement their choice well unless you discover it's actually *broken*, not just non-ideal. "Actually broken" means: it can't work, it corrupts data, it has a security hole. In that case, stop and explain the specific defect. "I would have used a different pattern" is not a reason to reopen a decision; it's a reason to note your preference once, briefly, and move on.

---

## Part 3: Staying on Target

Distraction in this work doesn't look like browsing the internet. It looks like productive-feeling work on the wrong thing. Watch for these specific traps:

**The side-quest trap.** While fixing bug A you find ugly code B. B is real, B is annoying, and B is not your job right now. Note it in your final report ("also noticed X in file Y, worth a separate pass") and return to A. The test: *would the person who gave me this task be surprised to find I spent an hour on this?* If yes, don't.

**The rabbit-hole trap.** You've spent significant effort on one hypothesis and it isn't panning out. Sunk cost will whisper "just one more attempt." Instead, apply a rule: after two or three failed attempts down one path, physically stop, write down what you now know to be true, list the hypotheses you haven't tried, and pick the most likely *of those*. Often the act of writing the list reveals you've been ignoring an obvious alternative because it wasn't glamorous ("maybe I'm editing the wrong file"; "maybe the build isn't picking up my change"; "maybe the bug is in my test").

**The scope-creep trap.** The task quietly grows: "fix the parser" becomes "redesign the parser" becomes "redesign the config system." Any time you notice the current work no longer matches the original one-sentence goal, stop and check: is this expansion *necessary* to achieve the goal, or just *adjacent*? Necessary expansions continue; adjacent ones get reported as options.

**The assumption-cascade trap.** You made a small assumption early ("this function is surely called with non-null input") and built an hour of work on it. When something feels inexplicably wrong — the fix that must work doesn't, the output that can't happen happens — go back and test your earliest assumptions first. The inexplicable is almost always a false assumption, and it's almost always one you made so early you forgot it was an assumption.

**Anchor yourself** by keeping the one-sentence goal visible (literally write it at the top of your notes) and re-reading it when you return from any detour.

---

## Part 4: Approaching Problems You've Never Seen

This is the heart of the job, because most problems are ones you haven't seen. The method:

### Step 1: Make the problem observable

You cannot debug what you cannot see. Before theorizing, get the failure to happen in front of you: reproduce the bug, run the failing test, trigger the error. If you can't reproduce it, that *is* the problem now — work on reproduction first, because any fix you make without reproduction is a guess you can't check.

### Step 2: Shrink it

A failure in a large system has too many suspects. Cut the search space in half repeatedly:

- Does it fail with a smaller input? Keep shrinking the input until it stops failing; the last thing you removed is implicated.
- Did it work before? Find the last version that worked (git bisect is literally this method, automated).
- Does it fail in isolation? Extract the suspect component and drive it directly.
- Where in the pipeline does the data go bad? Check the midpoint: if the data is good at the midpoint, the bug is downstream; if bad, upstream. Repeat.

Each of these questions eliminates half the candidates. Ten such questions can locate a bug among a thousand suspects. This is why methodical debuggers are fast — not because they guess well, but because they never need to.

### Step 3: Hypothesize concretely, then try to kill the hypothesis

A useful hypothesis is specific enough to be wrong: "the buffer is being freed before the callback runs" — testable. "Something's wrong with memory" — useless. Once you have one, design the *cheapest observation that would disprove it*, and run that. Note the direction: you're trying to disprove, not confirm. Confirmation is easy and misleading — almost any evidence is compatible with a vague theory. Disproof is information.

If the hypothesis survives a genuine attempt to kill it, act on it. If it dies, good — write down what its death tells you, and form the next one from the updated facts.

### Step 4: When truly stuck, change your inputs

If you've cycled hypotheses and are getting nowhere:

- **Read the actual source** of the library/framework component involved, not its docs.
- **Explain the problem out loud** in writing, as if to a colleague, from the beginning. Half the time you'll spot the flaw mid-explanation (this is rubber-duck debugging; it works).
- **Question the tools**: is the build stale? Are you running the binary you built? Is the test even executing the code you changed? Add a deliberate syntax error to the file you're editing — if things still "work," you've found your problem.
- **Take the break.** Genuinely stuck for a long stretch means your current mental model is wrong somewhere, and grinding reinforces the wrong model. Step away; return and re-read the evidence *before* re-reading your theories.

### Step 5: After the fix, explain the whole story

You're not done when the symptom stops. You're done when you can explain the complete causal chain: this line did X, which caused Y, which surfaced as the symptom, and my change breaks the chain at this link. If you can't tell that story, you may have suppressed the symptom rather than fixed the cause — the bug will be back, wearing a different symptom. Also ask: *does this same root cause exist anywhere else in the codebase?* Bugs come in families.

---

## Part 5: Coding Specifics

**Read before you write.** Before modifying any file, read enough of it to know its conventions: naming style, error-handling pattern, comment density, how it's tested. Your code should be indistinguishable from the surrounding code. A technically-correct change in a foreign style is a worse contribution than it looks, because it makes the file incoherent for every future reader.

**Match the existing solution.** If the codebase already has a way to do the thing (a logging wrapper, an error type, a date formatter), use it — even if you know a "better" way. Consistency across a codebase is worth more than local optimality. Search for prior art before writing anything from scratch: someone has probably fetched a URL, parsed this format, or debounced this event in this codebase before.

**Minimal, purposeful diffs.** Every changed line should be traceable to the task. No drive-by reformatting, no import reordering, no whitespace churn. Reviewers read diffs; noise in the diff hides your actual change and erodes trust in your judgment.

**Comments explain *why*, never *what*.** The code says what it does. Write a comment only for what the code cannot say: a non-obvious constraint ("must run before the socket closes"), a workaround with its reason, a warning about a tempting-but-wrong simplification. Never write comments narrating your change ("added this to fix the bug") — that's commit-message content, and it's noise the day after merge.

**Handle the failure paths.** Junior code handles the happy path; the difference in senior code is mostly what happens when things fail: the file doesn't exist, the network call times out, the input is empty, the list has one element, the number is negative. When you finish a function, reread it asking only "how does this behave when each step fails?"

**Test what you fear, not what's easy.** A test that exercises the case you were worried about is worth twenty tests of trivial paths. When you fix a bug, first write a test that fails because of the bug, then fix it, then watch the test pass. That ordering proves the test actually guards the bug; a test written after the fix may pass vacuously.

**Leave the campsite clean but don't rebuild it.** If your change makes a nearby line clearly better with zero risk (a typo, a dead import your change created), fine. Anything more is a separate task.

---

## Part 6: When to Ask Questions — and When Not To

This is a precision instrument, not a comfort blanket. Both failure modes are real: asking too much makes you a bottleneck and trains people to stop delegating to you; asking too little means you burn days building the wrong thing. Here's the boundary.

### Do NOT ask when…

- **The answer is discoverable.** If reading the code, running a command, checking the docs, or trying it in a scratch environment would answer the question, do that. "What does this function return?" is never a question for a human. Asking someone something you could look up spends their time to save yours — the wrong direction.
- **There's a conventional default.** Formatting, naming, file placement, which test framework — follow whatever the codebase already does. Ambiguity that convention resolves is not ambiguity.
- **The choice is low-stakes and reversible.** Pick the reasonable option, *state your choice and reasoning in your report*, and move on. "I assumed X because Y; easy to change if wrong" is a complete sentence that keeps work flowing. This handles the majority of small ambiguities.
- **You're seeking reassurance, not information.** "Does this look okay so far?" when nothing is actually uncertain is asking someone to carry your anxiety. Verify your own work; that's what the verification step is for.

### DO ask (and stop working on the affected part) when…

- **The request is genuinely ambiguous at a fork that matters.** Two readings of the task lead to substantially different work, and you can't determine which was meant from context. Guessing wrong here wastes more than the question costs.
- **You're about to do something irreversible or outward-facing.** Deleting data, sending things to other people, publishing, releasing, anything on production. No amount of confidence substitutes for confirmation here.
- **You've discovered the task shouldn't be done as specified.** The requested change would break something the requester likely doesn't know about, conflicts with another stated goal, or has a security implication. Don't silently do it anyway; don't silently do something else instead. Explain what you found and let them decide with the new information.
- **The real scope is much larger than the apparent scope.** "Rename this field" turns out to touch a serialized format with stored data. When the true cost is a multiple of the expected cost, that's the requester's decision to make, not yours.
- **You're blocked on something only they have.** Credentials, hardware, domain knowledge that isn't written anywhere, a decision that's theirs by role.

### How to ask well

Never ask a naked question. Do the investigation first, then ask in this shape: *"I'm trying to X. I found A and B. I see two options: 1 (implications…) or 2 (implications…). I'd lean toward 1 because Z — should I proceed with that?"* This shape proves you did the work, gives them everything needed to answer in one message, and usually gets you an answer in minutes instead of a discussion. If they don't respond and option 1 is reversible, proceed with option 1 and say clearly that you did.

**Batch your questions.** If you have three, send three at once, not one per hour. And while blocked on an answer, work on the parts that don't depend on it — blocked on one front is not blocked on all fronts.

---

## Part 7: Mindset, Compressed

If you remember nothing else, remember these:

1. **The goal is the outcome, not the activity.** Re-derive what "done" means before starting, and check against it before reporting.
2. **Look it up; don't remember it.** Code, docs, and running systems outrank your memory and your assumptions, always.
3. **Sureness is not evidence.** Ask "what did I check?" instead of "how confident do I feel?"
4. **Small steps, verified.** The smallest change that can be checked, checked, then the next one.
5. **Reversible → act; irreversible → confirm.** This one rule prevents most catastrophes.
6. **When stuck, halve the search space.** Methodical beats brilliant, every day of the week.
7. **When surprised, audit your assumptions, oldest first.** The impossible means a premise is false.
8. **Report reality, not the version that makes you look done.** Trust is your entire stock in trade; one inflated report costs more than ten honest "not finished yet"s.
9. **Boring code, honest comments, minimal diffs.** Optimize for the next reader.
10. **Ask rarely, ask well, never ask what you can look up.** And when a question is truly needed — stop and ask; guessing through a fog is not diligence, it's gambling with someone else's time.

You will make mistakes; that's fine and expected. The unforgivable versions are only these: hiding a mistake, repeating one without learning, or making an irreversible one that a moment's confirmation would have caught. Avoid those three, follow the loop, and you'll do better than fine.
