# Ralph TTS — Agent Prompt

## Context files (read every iteration)

| Doc | Path |
|-----|------|
| Spec | `ralph-tts/spec.md` |
| Plan | `ralph-tts/plan.md` |
| Concept list | `ralph-tts/concepts.json` |
| Progress | `ralph-tts/progress.txt` |
| Voice reference | `mlops/concepts/01-data-validation.html` |

## Rules

1. Read `ralph-tts/plan.md` — pick **exactly ONE** unchecked item, the first one.
2. Read `ralph-tts/concepts.json` for that entry — especially `description`
   (what the page must cover), `viz` (what the demo must do), `depth` (the word
   floor) and `has_code`.
3. Write the page at `tts/concepts/<id>.html`.
4. Self-validate: `bash ralph-tts/validate.sh <id>`.
5. Fix anything it reports, then re-check.
6. After passing: tick the item in `ralph-tts/plan.md` and append one line to
   `ralph-tts/progress.txt`.
7. If ALL items are done, emit `<promise>COMPLETE</promise>`.

## One concept per run — do not start the next plan item.

## Who is reading this

Someone preparing for a **Senior ML / GenAI Engineer, Voice & Speech** interview
at a company running real-time voice over telephony in healthcare. They will be
asked to reason out loud about latency budgets, why a voice agent talks over the
caller, and what a phone line does to a 24 kHz voice. Write for that person.

Four standing instructions follow from it:

- **Put the milliseconds in.** Where a topic has a latency cost, state it and
  show where it lands in an 800 ms budget. "Adds latency" is not an answer.
- **Assume a phone call.** 8 kHz narrowband, mu-law, jitter, packet loss. A page
  that reasons only about clean studio audio is half a page.
- **Assume PHI.** Recorded voice in healthcare is regulated. Where retention,
  consent or caller disclosure bear on the topic, say so concretely.
- **Keep the cascade-versus-speech-to-speech trade honest.** Neither is the
  obvious winner; interviewers probe exactly this.

## File structure

Match the structure and styling of the voice reference page. Required:

```html
<header>…title, group, depth…</header>
<section id="theory">…</section>
<section id="visualization">…interactive demo…</section>
<section id="interview-line">…</section>
<section id="takeaways">…4–6 bullets…</section>
<nav class="concept-nav">…prev / next…</nav>
```

Self-contained: no local asset files, no CDN scripts. Google Fonts is the only
permitted off-origin reference. All CSS and JS inline.

### Theory
Explain the mechanism, not the vocabulary.

**Depth sets a RANGE, and the upper bound is as binding as the lower:**

| depth | theory words | whole file |
|---|---|---|
| `intro` | 300–450 | ≤ 25 KB |
| `core` | 500–750 | ≤ 30 KB |
| `advanced` | 700–1000 | ≤ 35 KB |

Do not pad to reach the floor, and do not sail past the ceiling because you have
more to say. You almost always will have more to say — this is reference
material for someone rehearsing answers under time pressure, and a tight 500
words they will actually reread beats 1400 they will skim once. If a topic
genuinely does not fit, it is two concepts, not one long page; say so in the
takeaways rather than expanding.

The visualization is where the depth goes, not the prose.

Name the characteristic failure mode. Every architecture here has one, and it is
usually the interview question: attention collapsing into babble, an endpointer
cutting the caller off mid-sentence, a vocoder buzzing on out-of-domain mel,
a cloned voice that carries the reference clip's room reverb.

### Visualization
Build what the entry's `viz` field describes: a real event listener or animation
loop, driven by controls the reader can move, with the numbers updating live. A
static diagram is a fail.

**Do not build a test harness for it.** Write the visualization, then run
`bash ralph-tts/validate.sh <id>` and act on what it reports. Do not extract the
page's JS to a scratch file, do not benchmark redraw times in Node, do not write
throwaway harness scripts. Reading the code you just wrote is the expected level
of checking; an iteration that spends minutes proving its own canvas is fast is
spending your budget on the wrong thing.

Where the topic is audible, prefer showing the *spectral or timing consequence*
visually over attempting audio synthesis in the browser.

### Interview line
The two or three sentences you would actually say when asked this cold. Not a
summary of the page — the spoken answer, in the register a person uses out loud.

### Code blocks
`has_code: true` requires at least one `<pre>` with real code-shaped content.
Use it for the small piece of maths or scheduling logic the prose describes —
a mel filterbank construction, a jitter buffer's playout decision, an RTF-to-GPU
derivation. Not a toy snippet unrelated to the argument.

## Two gates run after you finish — you cannot bypass either

1. `bash ralph-tts/validate.sh <id>` — its exit code is honoured. Sections,
   depth floor, self-containment, code block, interactivity, title coverage.
2. **An independent fact-check agent** is given your finished file and nothing
   else. It is told it did not write it, and asked to find any incorrect
   formula, wrong mechanism or false claim. It does not see your reasoning.

So get the facts right the first time. Specifically, in this domain:

- Sample rates, frame rates and hop lengths must be internally consistent — if
  you say 12.5 ms hop at 22.05 kHz, the frame count you quote later must match.
- Do not invent MOS scores, RTF figures or model parameter counts. Cite one you
  can stand behind or mark it explicitly as illustrative.
- Get the direction of the trade right. Non-autoregressive is faster and more
  predictable, *not* more natural. Larger jitter buffers cost latency and buy
  robustness, not the reverse.
- Do not claim a technique solves a problem it merely mitigates. Watermarking
  survives some transcodes, not all.

If rejected, you will be shown the exact `FAIL:` lines. Fix the underlying fact
or the underlying code — do not reword around it.
