# stockcast: out-of-sample forecasting of daily equity returns and volatility

[![R package CI](https://github.com/SatvikPraveen/Stock-Price-Prediction/actions/workflows/r-tests.yml/badge.svg)](https://github.com/SatvikPraveen/Stock-Price-Prediction/actions/workflows/r-tests.yml)
![License](https://img.shields.io/github/license/SatvikPraveen/stock-price-prediction)
![R](https://img.shields.io/badge/R-%E2%89%A5%204.2-blue?logo=r)
[![Live app](https://img.shields.io/badge/Shiny-live%20dashboard-75AADB?logo=rstudio)](https://my-app-01.shinyapps.io/shiny_app/)

A reproducible research framework, packaged as R package **`stockcast`**, that asks a precise question:
**can standard statistical and machine-learning models forecast next-day equity returns better than a random walk once the evaluation is genuinely out of sample, and how well can their variance be forecast?**

Every number in this README is produced by `make experiment` from a pinned data snapshot, scored with proper scoring rules, and tested against a benchmark with formal statistics. Nothing is fitted in-sample and reported as a forecast.

## What the study does

- **Data.** Daily OHLCV for 10 large-cap US names and SPY, 2010 to 2026, from Yahoo Finance, pinned to SHA-256-hashed CSVs in [`data/snapshot/`](data/snapshot/) so that a run is bit-for-bit reproducible.
- **Targets.** `h`-day cumulative log returns (`h` = 1, 5) and their variance, proxied by squared returns and Garman-Klass realised variance from OHLC.
- **Models.** Eight return forecasters (random walk, drift, ARIMA, ETS, STL-ETS, elastic net, random forest, ARMA-GARCH) and five variance forecasters (rolling variance, EWMA, GARCH(1,1), two HAR-RV variants), all behind one `fit()` / `predict()` interface.
- **Protocol.** Rolling-origin walk-forward with an origin on **every trading day** (about 3,200 per ticker), parameters refit monthly and frozen in between, realised targets attached only from the future window. Failures are caught per origin instead of aborting the run.
- **Scoring.** RMSE, MAE, Campbell-Thompson out-of-sample R², CRPS, interval coverage and Winkler score for returns; QLIKE and MSE for variance. **Diebold-Mariano** tests (HLN small-sample correction, overlap-aware) against the benchmark and the **Pesaran-Timmermann** directional test.
- **Economics.** Long/flat and long/short strategies from the sign of the forecast with 5 bp transaction costs; Sharpe ratios with Lo (2002) standard errors, drawdowns and turnover, against buy-and-hold.

Full details, references and limitations: [`docs/methodology.md`](docs/methodology.md).

## Results

<!-- results:start -->
_Results are being generated; see `results/latest/` once the full run is committed._
<!-- results:end -->

## Why this matters

The project started as a Shiny app that "predicted" the closing price from the same day's open, high and low, plus a notebook whose ARIMA/STLF comparison scored a 30-day-ahead forecast against the *last 30 days of its own training data* (a MAPE of about 1% that meant nothing). The rebuild keeps the STL-ETS specification in the model registry precisely so the difference between an in-sample number and a walk-forward one is visible: under a valid protocol it is significantly worse than a random walk. The old outputs are preserved in [`results/legacy_notebook/`](results/legacy_notebook/) and the notebook carries an explanatory note.

## Repository layout

```
R/                      package source: data, features, models, backtest, metrics, strategy, report
tests/testthat/         unit tests on synthetic data (no network), plus a headless test of the app
config/                 experiment.yml (full) and quick.yml (smoke)
scripts/                snapshot_data.R, run_experiment.R, render_report.R, update_readme.R
data/snapshot/          pinned OHLCV CSVs + MANIFEST.json with SHA-256 hashes
results/latest/         tables, figures and provenance of the committed run
results/runs/<id>/      every run (git-ignored): forecasts.rds, config, sessionInfo, provenance
reports/report.Rmd      auto-generated HTML report
shiny_app/              bslib dashboard
docs/methodology.md     protocol, metrics, references
Dockerfile, Makefile    reproducible environment and entry points
```

## Reproduce

```bash
git clone https://github.com/SatvikPraveen/Stock-Price-Prediction.git
cd Stock-Price-Prediction
make deps          # R >= 4.2; installs everything in DESCRIPTION via pak
make install       # needed so parallel workers can load the package
make test          # 60+ tests, no network required
make quick         # ~5-minute smoke run: 2 tickers, weekly origins
make experiment    # full run: ~50 minutes on 8-9 cores
make report        # reports/report.html from results/latest
make app           # launch the dashboard locally
```

Or, with nothing but Docker installed:

```bash
make docker && make docker-run
```

To refresh the data (this changes every result, so treat it as a new experiment): `make data`.

### Compute requirements

The full experiment is about 830,000 forecasts and takes roughly 50 minutes on a 10-core laptop with 9 `future` workers; no GPU or cluster is needed. The work is embarrassingly parallel over (ticker, horizon) tasks, so scaling to hundreds of tickers or intraday data only requires pointing `future::plan()` at a cluster backend such as `future.batchtools` for SLURM.

## Using the package

```r
library(stockcast)
prices <- get_prices("AAPL")                       # from the snapshot; refresh = TRUE to download
feat   <- make_features(prices$AAPL)               # strictly lagged predictors
fc     <- walk_forward(feat, get_models(c("naive_zero", "arima", "garch11")),
                       h = 1, initial = 1000, step = 1, refit_every = 21)
evaluate_forecasts(fc)                             # RMSE, OOS R², DM and PT tests, CRPS, QLIKE ...
backtest_strategy(fc, cost_bps = 5)                # Sharpe, drawdown vs buy-and-hold
dm_test(e1, e2, h = 5)                             # Diebold-Mariano with HLN correction
```

Adding a model is one constructor returning `new_model()`; see [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Dashboard

The [live dashboard](https://my-app-01.shinyapps.io/shiny_app/) (auto-deployed from `main` after CI passes) lets you pick any ticker in the snapshot or download one live, view prices with moving averages and Bollinger bands, produce a genuine `h`-day-ahead price forecast with a 95% interval from any registered model next to the random-walk benchmark, compare GARCH conditional volatility with realised volatility, and browse the walk-forward leaderboards and tests.

## Citation

If you use this code or its results, please cite it (see [`CITATION.cff`](CITATION.cff)):

> Praveen, S. (2026). *stockcast: walk-forward evaluation of daily equity return and volatility forecasts* (v1.0.0). https://github.com/SatvikPraveen/Stock-Price-Prediction

## License

MIT. See [`LICENSE.md`](LICENSE.md).
