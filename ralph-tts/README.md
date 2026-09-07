# Ralph TTS — Text-to-Speech & Voice AI Concepts

Generates 32 interactive concept pages under `tts/concepts/`, one per topic.

## Why this track exists

The repo had effectively no speech coverage. A survey before this track was
written found **zero** files mentioning text-to-speech, vocoder, mel-spectrogram,
phoneme, prosody, Tacotron or WaveNet — the only hits were incidental uses of
"TTS" and "Whisper" inside `ai-engineering/concepts/31-agents-overview.html`.

## What it is aimed at

A **Senior ML / GenAI Engineer, Voice & Speech** interview at a company running
real-time voice over telephony in healthcare. That aim is why the queue leans
where it does: 6 of 32 topics are streaming, latency and turn-taking, and
telephony audio constraints get a page of their own rather than a footnote.

A generic TTS curriculum would spend that budget on concatenative and
HMM-parametric synthesis. Those are omitted deliberately — historically
interesting, no longer plausible interview ground for a 2026 voice role.

## Topics

| Group | n | Covers |
|---|---|---|
| audio | 5 | sampling, mel scale, **telephony constraints**, jitter/loss, VAD |
| text | 4 | normalization, G2P, prosody, **forced alignment** |
| architectures | 5 | Tacotron 2, attention failures, FastSpeech 2, AR vs NAR, VITS |
| vocoders | 4 | WaveNet, Griffin-Lim, HiFi-GAN, neural codecs & RVQ |
| streaming | 6 | **streaming TTS, latency budget, barge-in, turn-taking, speech-to-speech, RTF/GPU sizing** |
| identity | 4 | speaker embeddings, zero-shot cloning, style control, **watermarking & consent** |
| evaluation | 4 | MOS/CMOS, objective metrics, serving cost, **voice-agent regression testing** |

Bold entries exist because of this specific role. Depth: 2 intro / 18 core /
12 advanced. 23 of 32 require a code block.

## Quick start

```bash
# 1. build the plan from concepts.json
./ralph-tts/scaffold.sh

# 2a. one concept — next in queue
./ralph-tts/once.sh

# 2b. a specific concept
./ralph-tts/once.sh 21-barge-in

# 3. canary: one iteration through the real loop
./ralph-tts/loop.sh 1

# 4. full run
RALPH_LOOP_SLEEP=15 ./ralph-tts/loop.sh

# 5. validate
./ralph-tts/validate.sh
./ralph-tts/validate.sh 21-barge-in

# 6. cross-file redundancy, and the end-of-run completeness gate
../validate-corpus.sh tts
../validate-corpus.sh --final tts
```

## Binding validation

No `|| true` anywhere. This track inherits the full hardened harness:

- `once.sh` honours `validate.sh`'s exit code, and checks the file actually
  exists before believing a pass — an ungenerated item is SKIPped and returns 0
- failures feed the exact `FAIL:` lines into the next attempt's prompt
- capped at `RALPH_MAX_ATTEMPTS` (3), then exits 3
- an adversarial fact-check must PASS, and its verdict is written to
  `progress.txt` as `| gate | validate=PASS factcheck=PASS attempts=N`
- a fact-check *harness* failure exits 4 rather than burning the retry budget
- an unaccepted draft is quarantined as `.partial`, never left in the corpus
- `COMPLETE` requires every planned item to exist **and** the corpus gate to pass
- `loop.sh` stops on any unexpected exit code, and after 3 no-output iterations
- every agent run writes a `<log>.status` sidecar with an interpreted exit code

## Environment

| Var | Default | Effect |
|---|---|---|
| `RALPH_TTS_MODEL` | — | Model slug for generation |
| `RALPH_TTS_TIMEOUT` | 3600 | Seconds per generation attempt |
| `RALPH_MAX_ATTEMPTS` | 3 | Rejections before the run gives up |
| `RALPH_SKIP_FACTCHECK` | 0 | `1` skips the adversarial pass — recorded as `factcheck=SKIPPED` |
| `RALPH_FACTCHECK_TIMEOUT` | 900 | Seconds for the fact-check pass |
| `RALPH_LOOP_SLEEP` | 5 | Seconds between loop iterations |
| `RALPH_MAX_STALLS` | 3 | Consecutive no-output iterations before stopping |
| `RALPH_CORPUS_FINAL` | — | `1` makes `validate-corpus.sh` apply its completeness gate |

## Files

```
ralph-tts/
├── spec.md         what a page must contain, and who it is aimed at
├── prompt.md       the agent's per-iteration instructions
├── concepts.json   the 32-topic queue + description + viz + depth + has_code
├── plan.md         queue (built by scaffold.sh)
├── progress.txt    append-only run log, including harness gate lines
├── scaffold.sh     builds plan.md from concepts.json
├── once.sh         one concept, binding validation + fact-check
├── loop.sh         runs once.sh until done
└── validate.sh     per-page structural checks
```

Shared helpers live in `../ralph-common.sh`.
