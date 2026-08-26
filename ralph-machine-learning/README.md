# Ralph Machine Learning — Interactive HTML Generator

Generates **self-contained interactive HTML files** for classical ML / Data Science interview concepts — one file per concept, theory + live visualization. Built on the same base as `ralph-concepts/`, retargeted at `machine_learning/` instead of `ai-engineering/`.

## Quick start

```bash
# 1. Scaffold the plan
./ralph-machine-learning/scaffold.sh

# 2a. Generate one concept — next in queue
./ralph-machine-learning/once.sh

# 2b. Generate a specific concept by id
./ralph-machine-learning/once.sh 14-gradient-boosting

# 3a. Run the full loop (all 38)
./ralph-machine-learning/loop.sh

# 3b. Run a specific concept (useful to retry a failed one)
./ralph-machine-learning/loop.sh 19-pca

# 4. Validate all generated files
./ralph-machine-learning/validate.sh

# 4b. Validate a single concept
./ralph-machine-learning/validate.sh 19-pca
```

## See available concept IDs

```bash
./ralph-machine-learning/once.sh --help
```

## What it generates

For each of the 38 concepts in `concepts.json`, one HTML file at:
```
machine_learning/concepts/<id>.html
```

Each file is **fully self-contained** — open directly in a browser, no server needed.

### HTML structure
| Section | Content |
|---------|---------|
| `<header>` | Title, group badge, one-sentence description |
| `#theory` | Deep theory: mechanism, tradeoffs, real numbers, production context |
| `#visualization` | Interactive JS viz (vanilla JS + Canvas/SVG, no CDN) — prefers running the real algorithm client-side over a canned animation |
| `#takeaways` | 4–6 senior-level insights |
| `.concept-nav` | Prev/next navigation between concepts |

## Scope vs `ai-engineering/categories/06-ml-fundamentals.md`

That category already covers classical ML at intro depth for LLM/AI-engineer interviews. This track goes deeper and broader — dedicated ML Engineer / Data Scientist interview prep: statistics, algorithms, ensembles, unsupervised learning, DL fundamentals, ML system design, MLOps-adjacent topics. See `spec.md` § Scope note.

## Concepts (38 total)

| Group | Concepts |
|-------|---------|
| **Foundations** | Bias-Variance Tradeoff, Bayes' Theorem, Central Limit Theorem, Hypothesis Testing, MLE vs MAP |
| **Supervised** | Linear Regression, Logistic Regression, SVM & Margins, Decision Trees, kNN, Naive Bayes |
| **Ensembles** | Bagging vs Boosting, Random Forest, Gradient Boosting, Stacking |
| **Unsupervised** | k-Means, Hierarchical Clustering, DBSCAN, PCA, t-SNE/UMAP |
| **Evaluation** | Cross-Validation, Confusion Matrix & Metrics, ROC vs PR Curves, Learning Curves |
| **Optimization** | Gradient Descent Variants, L1 vs L2 Regularization, Dropout & BatchNorm |
| **Deep Learning** | Backpropagation, CNNs & Convolution, RNN/LSTM/GRU, Weight Init & Vanishing Gradients |
| **Feature Engineering** | Feature Scaling, Categorical Encoding, Imbalanced Data Handling |
| **Systems** | Recommender Systems, A/B Testing for ML Products |
| **Time Series** | Time Series Decomposition, ARIMA Forecasting |

## Scripts

| Script | Purpose |
|--------|---------|
| `scaffold.sh` | Build/refresh `plan.md` from `concepts.json` |
| `once.sh [--model slug]` | Generate ONE concept (pick from plan.md) |
| `loop.sh [max] [--model slug]` | Loop all 38 concepts |
| `validate.sh [concept-id]` | Structural validation of generated HTML files |

## Design system

Matches the dark terminal theme used across the rest of the repo's HTML suite:
- Background: `#0d0f17`
- Accent: `#00d4ff` (cyan)
- Fonts: Inter + JetBrains Mono (Google Fonts CDN)
- No other external dependencies

## Testing

Each concept is tested by the generating agent via **Playwright MCP**:
1. Navigate to the file URL
2. Screenshot to confirm render
3. Check console for JS errors
4. Fix and re-test if needed

## Environment variables

| Var | Default | Description |
|-----|---------|-------------|
| `RALPH_ML_MODEL` | (claude default) | Model slug to use |
| `RALPH_ML_TIMEOUT` | `3600` | Agent timeout in seconds |
