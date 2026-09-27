# Changelog

## 1.0.0 (2026-09-27)

Complete rebuild of the project as the `stockcast` R package.

### Added
- Rolling-origin walk-forward evaluation engine with periodic refits and
  per-origin error capture (`walk_forward()`, `run_experiment()`).
- Model registry with 8 return forecasters (random walk, drift, ARIMA, ETS,
  STL-ETS, elastic net, random forest, ARMA-GARCH) and 5 variance
  forecasters (rolling variance, EWMA, GARCH(1,1), two HAR-RV variants).
- Strictly lagged feature set including Garman-Klass realised variance.
- Proper scoring rules (RMSE, MAE, OOS R², CRPS, Winkler, QLIKE) and formal
  tests (Diebold-Mariano with HLN correction, Pesaran-Timmermann).
- Cost-aware trading backtest with Sharpe standard errors.
- Hashed data snapshot for a 10-ticker universe (2010-2026) with manifest.
- Experiment configs, run scripts, auto-generated HTML report, Makefile,
  Dockerfile, CITATION.cff.
- 40+ unit tests on synthetic data; CI runs R CMD check, lint and a smoke
  experiment on Linux and macOS.
- Rebuilt Shiny dashboard: multi-ticker, genuine h-day-ahead forecasts with
  intervals from any registered model, volatility tab, and the walk-forward
  leaderboards.

### Changed
- README now reports out-of-sample results with significance tests instead
  of in-sample fit statistics.
- The notebook's original outputs moved to `results/legacy_notebook/`, and
  the notebook carries a note explaining why its evaluation was invalid.

### Removed
- The same-day OHLC "closing price predictor" (Close is bounded by the
  same day's High and Low, so it was not a forecast).
- Python `setup.py` / `requirements.txt` scaffolding and `dependencies.R`;
  dependencies are declared in `DESCRIPTION`.
