# Debug model that runs but doesn't learn — broadcasting, dimension mismatches?

**Category:** 06-ml-fundamentals
**Question #:** 013
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing practical debugging depth — whether you have actually trained neural networks end-to-end and diagnosed silent failures. Models that compile and run without errors but never improve are the most insidious class of ML bugs; catching them requires a systematic checklist, not guesswork.

### Trigger phrases
- "Your model trains but loss doesn't go down — what do you do?"
- "Walk me through debugging a neural network that isn't learning."
- "What are common PyTorch bugs that cause a model to fail silently?"

### What it tests
Systematic ML debugging instinct: ability to isolate data, model, and optimizer bugs in priority order.

---

## Answer

### Concept
A model that "runs but doesn't learn" means the training loop executes without crashing but loss stagnates, diverges, or never falls below a random baseline. The root causes fall into three buckets: **data pipeline bugs** (wrong labels, silent shape errors, normalisation mistakes), **model architecture bugs** (broadcasting masks real errors, dead activations, gradient blocking), and **optimiser mis-configuration** (learning rate, loss reduction, detached tensors). Broadcasting in PyTorch/NumPy silently reshapes mismatched tensors instead of erroring, which is the single most common source of "shape looks fine but output is noise."

### Mechanism

**Step 1 — Sanity-check with a mini-batch overfit test**  
Run `N=1` (or 32) examples for 100+ steps. A correctly wired model must overfit a tiny batch to near-zero loss. If it can't, the bug is in the model or loss, not the data scale.

**Step 2 — Validate data pipeline**  
- Print `X.shape`, `y.shape`, dtype, and a handful of `(X[i], y[i])` pairs.  
- Check label alignment: shuffle bugs and index-off-by-one errors produce random labels.  
- Confirm normalisation is applied identically at train and serve time (training/serving skew).

**Step 3 — Check for broadcasting traps**  
```python
# Silent broadcasting bug — no error, wrong semantics
loss = criterion(logits, labels)      # logits: (B, C), labels: (B,) — OK
loss = criterion(logits, labels.T)    # (B, C) vs (1, B) — broadcasts silently, wrong loss
```
Use `assert logits.shape == expected_shape` before the loss call. Enable `torch.set_default_dtype(torch.float32)` and add explicit `reshape`/`unsqueeze` calls.

**Step 4 — Inspect gradients**  
```python
torch.autograd.set_detect_anomaly(True)   # raises on NaN/Inf gradients
for name, p in model.named_parameters():
    if p.grad is None:
        print(f"NO GRAD: {name}")          # detached tensor or unused parameter
    else:
        print(name, p.grad.abs().mean())   # vanishing (<1e-7) or exploding (>1e2)
```
Common culprits: using `.numpy()` inside the forward pass (detaches grad), `loss.item()` before `.backward()`, forgetting `optimizer.zero_grad()`.

**Step 5 — Check learning rate and loss scale**  
- LR too high → loss explodes or oscillates.  
- LR too low → loss barely moves for many epochs.  
- Use `loss.mean()` not `loss.sum()` unless batch size is constant; sum-reduction with variable batch size causes effective-LR variance.

**Step 6 — Visualise activations and weights**  
Use `torchinfo.summary(model, input_size=...)` to confirm layer shapes. Check for dead ReLU layers (all-zero activation tensors) with forward hooks.

### Example / Tradeoff

**Concrete incident:** Training a BERT-based intent classifier. Loss plateaued at `ln(num_classes)` (random-chance baseline) after 2 epochs. Mini-batch overfit test immediately showed the tiny batch also failed to learn → data pipeline eliminated as root cause. Gradient check revealed `None` gradients on the BERT encoder — the embedding layer had been accidentally wrapped with `.detach()` during a copy-paste from an inference script. Fix: remove `.detach()`, rerun — loss dropped from 2.94 → 0.08 in 20 steps.

**Broadcasting trap example:** Transformer positional encoding added as `(1, seq_len, d_model)` to input `(batch, seq_len, d_model)` — correct broadcasting. But if someone passes `(seq_len, d_model)` without the leading 1, PyTorch broadcasts across batch dimension silently and training still runs with corrupted positional signals.

---

## Verbal script

**Opening (30s):**
"This is one of the trickiest classes of ML bugs because everything appears to be working — no exceptions, no NaNs at first glance. My approach is a systematic five-step checklist that isolates data, model, and optimizer as separate failure domains."

**Core explanation (2–3 min):**
"The first thing I do is a mini-batch overfit test: I take 32 examples and run 100+ gradient steps. Any correctly wired model must memorise those examples. If it can't, the bug is in the model or loss function, not in the size or quality of the data.

Next I validate the data pipeline — print raw shapes, dtypes, and a few (X, y) pairs to confirm labels are aligned. Shuffle bugs and off-by-one indexing errors produce random labels, which look like a non-learning model but are actually a data bug.

The broadcasting issue is the sneakiest: PyTorch will silently reshape tensors that don't match instead of throwing an error. I always add explicit `assert` statements on the shapes right before the loss call. For example, a labels tensor of shape (B,) that accidentally gets transposed becomes (1, B), which broadcasts against (B, C) logits and computes a meaningless loss without crashing.

Then I check gradients directly with `named_parameters()`. If any parameter has `.grad == None`, it means it's detached from the computation graph — usually from a stray `.numpy()` call or a `detach()` that was meant for inference code. I enable `torch.autograd.set_detect_anomaly(True)` to catch NaN gradients early. Finally I verify the learning rate scale — too high and loss explodes, too low and it barely moves for many epochs."

**Tradeoff / production angle (1 min):**
"At scale, anomaly detection adds overhead — I enable it only during debugging, not production training. For large models I also add forward hooks to sample activation statistics per layer. If a ReLU layer is returning all zeros, that's a dead-neuron problem that broadcasting checks won't catch. Weight initialisation matters here — using `nn.init.kaiming_uniform_` for ReLU networks prevents most dead-activation issues."

**Wrap-up (30s):**
"The key discipline is: never trust the training loop just because it doesn't crash. The overfit test is the single fastest gate — if your model can't memorise 32 examples in 100 steps, stop there and fix the model or loss before touching data scale."

---

## Pitfalls

- **Mistake:** Jumping straight to hyperparameter tuning (adjust LR, change optimizer) when the model isn't learning — **Better:** Run the mini-batch overfit test first; if the model can't overfit 32 examples, hyperparameter tuning will never fix the underlying structural bug.
- **Mistake:** Saying "check for NaN in the loss" as the primary debugging strategy — **Better:** Broadcasting bugs produce finite but meaningless loss values; always add explicit shape assertions before the loss call and check `p.grad is None` for every parameter.
- **Mistake:** Forgetting that `optimizer.zero_grad()` placement matters — placing it after `loss.backward()` but before the next `optimizer.step()` accumulates gradients from previous batches silently — **Better:** Always call `zero_grad()` at the top of the training loop before the forward pass.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q3: Diagnose performance bugs in a model?](06-003-diagnose-performance-bugs-in-a-model.md) | Parent diagnostic framework — covers broader perf issues beyond training bugs |
| [Q9: Bias-variance tradeoff?](06-009-bias-variance-tradeoff.md) | Follow-up once the model is learning — diagnosing under/overfitting |
| [Q22: Gradient descent?](06-022-gradient-descent.md) | Foundational mechanism — understanding why LR and gradient flow matter |

---

## One-liner recall

> Run a mini-batch overfit test first (32 examples, 100 steps); if it fails, add shape assertions before the loss call and check `p.grad is None` for every parameter to catch broadcasting traps and detached tensors before touching hyperparameters.
