# Ralph TTS — Spec

Generates **interactive text-to-speech and voice-AI concept pages** under
`tts/concepts/` — one self-contained HTML file per concept.

## Why this track exists

The repo had effectively nothing on speech. A survey before this track was
written found **zero** files mentioning text-to-speech, vocoder, mel-spectrogram,
phoneme, prosody, Tacotron or WaveNet; the only hits were passing uses of "TTS"
and "Whisper" inside `ai-engineering/concepts/31-agents-overview.html`.

## Who it is aimed at

A **Senior ML / GenAI Engineer, Voice & Speech** interview at a company running
real-time voice over telephony — the concrete target is Weave, a healthcare
communications platform serving ~30,000 practices, whose posting names
transcription, ASR pipelines with interruption detection, audio alignment and
speech synthesis, alongside low-latency voice agents and compliance-heavy design.

That aim changes the weighting, and pages should reflect it:

- **Latency is the through-line.** Almost every topic has a "what does this cost
  in milliseconds, and where in the budget does it land" angle. Prefer it.
- **Assume a phone call, not a demo.** 8 kHz narrowband, mu-law, jitter and
  packet loss are the deployment reality; a page that only reasons about clean
  24 kHz studio audio is half a page.
- **Assume PHI.** Recorded voice in a healthcare setting is regulated data.
  Where retention, consent or disclosure bear on a topic, say so concretely.
- **Cascade and speech-to-speech are both live options.** Do not present the
  ASR→LLM→TTS cascade as the only architecture, nor speech-to-speech as
  obviously superior; the trade is real and interviewers probe it.

## Output artifact per concept

| Attribute | Requirement |
|-----------|-------------|
| Path | `tts/concepts/<id>.html` |
| Format | Single self-contained HTML file — no local assets, no CDN |
| External refs | Google Fonts only; every other off-origin reference fails validation |

## Required sections

1. `<section id="theory">` — the explanation. Depth-scaled floor, below.
2. `<section id="visualization">` — an interactive demo, driven by the entry's
   `viz` field. Must have a real event listener or animation loop.
3. `<section id="interview-line">` — the two or three sentences you would
   actually say out loud when asked this in a round.
4. `<section id="takeaways">` — 4–6 bullets.
5. `class="concept-nav"` — prev/next links to sibling concept pages.

## Per-topic depth

`concepts.json` carries `depth`, which sets a theory-section word RANGE:
`intro` 300–450 / `core` 500–750 / `advanced` 700–1000, with whole-file ceilings
of 25/30/35 KB. The upper bound is deliberate — unbounded, generation ran 3x the
floor (964 words on a 300-word intro page) and cost roughly 3x the wall clock
per item for material a reader skims rather than rereads. The queue is 2 intro / 18 core /
12 advanced — this is a senior-level track and it is weighted accordingly.

`has_code` (23 of 32 entries) requires at least one `<pre>` block with
code-shaped content. For this track that usually means the small piece of
signal-processing or scheduling maths that the prose is describing.

## Quality rules

- **Show the arithmetic.** A latency or capacity claim without numbers is not
  useful in an interview. Derive it.
- **Name the failure mode.** Every architecture here has a characteristic way of
  breaking — attention collapse, endpointing cutting the caller off, a vocoder
  buzzing on out-of-domain mel. Say which one, and what it sounds like.
- **Be honest about what is still unsettled.** Full-duplex speech-to-speech
  versus the cascade is not a solved question; write it as a live trade.
- **No invented benchmark numbers.** If you cite an MOS or an RTF, it must be
  one you can stand behind, or framed explicitly as an illustrative figure.

## Enforcement — these gates are binding

`validate.sh` exit codes are honoured by `once.sh` and `loop.sh`. A failing
validation is never accepted, a `COMPLETE` promise is not believed unless
validation passes, and a rejected item is regenerated with the exact `FAIL:`
lines fed back into the next attempt. After 3 failed attempts the run stops with
an error rather than accepting unverified content.

A `COMPLETE` promise is checked against the corpus itself, not just against the
files in it. A per-file validator iterates over what exists, so on an empty or
half-finished corpus it checks nothing and reports a clean pass — right for a
mid-run sweep, and a lie for the final gate. `ralph_require_complete` closes it:
every item in `plan.md`, and every item in `concepts.json` in case the plan was
never re-scaffolded, must have produced a file. The same reasoning applies
per-item: an item the agent never wrote is SKIPped and passes, so `once.sh`
confirms the file exists before believing the validator.

A second, independent fact-check agent then reads the finished file — and only
that file — hunting incorrect formulas, wrong mechanisms and false claims. Its
PASS is required too, and the verdict is written into `progress.txt` so a later
reader can tell the gate actually ran.

### Loop safety

`loop.sh` stops on any exit code that is not "one item done, more remain";
three consecutive iterations that write no new file stop it with exit `5`; and
`RALPH_LOOP_SLEEP` (default 5s) paces iterations. An unaccepted draft is
quarantined as `.partial` rather than left in the corpus looking accepted.

`../validate-corpus.sh tts` flags near-duplicate explanations across the corpus.
`--final` (or `RALPH_CORPUS_FINAL=1`) additionally fails a corpus that is empty
or short of its queue — the end-of-run form of the same question
`ralph_require_complete` asks inside the loop.

## Progress log

```
2026-09-06 | 03-telephony-audio | Telephony Audio Constraints | OK
2026-09-06 | 03-telephony-audio | gate | validate=PASS factcheck=PASS attempts=1
```
