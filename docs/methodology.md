# Methodology

This document specifies the experimental protocol implemented by the
`stockcast` package. Everything described here is executed by
`scripts/run_experiment.R` from `config/experiment.yml`; nothing in the
reported results is produced by hand.

## 1. Research question

Can any of a set of standard statistical and machine-learning forecasters
predict **next-day (and next-week) log returns** of large-cap US equities
better than a **random walk**, once the evaluation is genuinely
out-of-sample? And, separately, how well can the **variance** of those
returns be forecast?

The two questions have very different answers in the literature (returns
are close to unpredictable at daily horizons; volatility is strongly
predictable), and a credible study has to be able to reproduce both.

## 2. Data

| Item | Value |
|---|---|
| Source | Yahoo Finance via `quantmod::getSymbols()` |
| Universe | AAPL, MSFT, AMZN, GOOGL, NVDA, JPM, XOM, JNJ, PG, SPY |
| Frequency | Daily OHLCV plus dividend/split-adjusted close |
| Sample | 2010-01-04 to the snapshot date in `data/snapshot/MANIFEST.json` |
| Pinning | Every CSV is committed with its SHA-256 in the manifest; `read_snapshot()` refuses to load a file whose hash has changed |

Yahoo's adjusted close is revised retroactively whenever a dividend is
paid, so re-downloading the "same" series later gives slightly different
returns. Pinning the snapshot is what makes a run reproducible.

Returns are **log returns on the adjusted close**. Realised variance uses
the **Garman-Klass (1980)** estimator on unadjusted OHLC, which is
unaffected by splits because it only uses same-day prices.

## 3. Targets

For a forecast origin `t` (the close of day `t`) and horizon `h`:

* **Return target**: `y_{t,h} = log P_{t+h} - log P_t`, the cumulative
  log return over the next `h` trading days.
* **Variance target**: the variance of `y_{t,h}`, proxied by
  (a) the sum of squared daily returns over `t+1..t+h` (conditionally
  unbiased, noisy) and (b) the sum of Garman-Klass daily variances (far
  less noisy, but excludes the overnight return and so is biased low).

Horizons: `h = 1` (primary) and `h = 5`.

## 4. Predictors

`make_features()` builds, for every day `t`, only quantities computable
from prices up to and including day `t`:

lagged returns (1-5 days), 5/21/63-day cumulative returns, 21-day return
volatility, 5/21-day mean Garman-Klass variance, RSI(14), MACD histogram,
Bollinger %B, log high/low range, and a 21-day z-score of log volume.

A unit test verifies causality: computing features on a truncated series
gives identical values on the overlapping rows.

## 5. Models

Every model exposes `fit(train, h)` and `predict(fit, train, h)`; see
`R/models.R`.

**Return forecasters** (output: mean and standard deviation of `y_{t,h}`)

| Name | Family | Description |
|---|---|---|
| `naive_zero` | benchmark | Random walk: mean 0, sd from the last 252 returns |
| `hist_mean` | benchmark | Expanding-window mean (random walk with drift) |
| `arima` | statistical | `auto.arima` on log price, non-seasonal |
| `ets` | statistical | ETS(A,Ad,N) on log price |
| `stlf` | statistical | STL (period 252) + ETS on log price; the original notebook's model |
| `elastic_net` | ML | Elastic net (alpha 0.5) on the predictors; blocked 5-fold CV |
| `random_forest` | ML | 500-tree random forest; out-of-bag sd |
| `arma_garch` | statistical | Constant mean + GARCH(1,1), Student-t innovations |

**Variance forecasters** (output: variance of `y_{t,h}`)

| Name | Family | Description |
|---|---|---|
| `hist_var` | benchmark | Rolling 21-day sample variance |
| `ewma` | benchmark | RiskMetrics EWMA, lambda 0.94 |
| `garch11` | statistical | GARCH(1,1), Student-t innovations |
| `har_gk` | statistical | HAR-RV (Corsi 2009) on Garman-Klass components, GK target |
| `har_r2` | statistical | HAR components as regressors, squared-return target |

## 6. Walk-forward protocol

`walk_forward()` implements a rolling-origin evaluation:

1. The first origin is observation 1000 (about four trading years).
2. Every subsequent trading day is an origin (`step = 1`), using an
   expanding window.
3. Parameters are re-estimated every 21 origins (monthly). Between refits
   the parameter vector is frozen and only the model state is updated
   with the new observations (`Arima(model = )`, `ets(model = )`,
   `stlm(model = )`, `ugarchforecast(spec with fixed.pars)`, or simply the
   newest feature row for the ML models).
4. Realised targets are attached from rows `t+1..t+h`; no model ever sees
   them.
5. Model failures are caught and recorded per origin rather than aborting
   the run.

This yields roughly 3,200 forecast origins per ticker and horizon, about
830,000 forecasts in total.

## 7. Scoring and inference

All comparisons are made on the **common sample** of origins where both
the model and the benchmark produced a finite forecast.

**Return forecasts**

* RMSE, MAE
* Out-of-sample R² relative to the random walk (Campbell & Thompson 2008)
* Directional accuracy and the Pesaran-Timmermann (1992) test
* CRPS of the Gaussian predictive distribution (Gneiting & Raftery 2007)
* 95% interval coverage and Winkler score
* Diebold-Mariano (1995) test of equal squared-error loss against the
  random walk, with the Harvey-Leybourne-Newbold (1997) small-sample
  correction and `h-1` autocovariance terms for overlapping targets

**Variance forecasts**

* QLIKE and MSE against both proxies (Patton 2011 shows these two are the
  losses robust to proxy noise)
* Diebold-Mariano tests on the QLIKE and MSE loss differentials against
  the rolling-variance benchmark

Results are reported per ticker and pooled across tickers.

## 8. Economic evaluation

`backtest_strategy()` turns `h = 1` forecasts into positions at the close
of the origin day (long if the forecast is positive, otherwise flat; a
long/short variant is also reported), charges 5 bp per unit of turnover,
and reports annualised return, volatility, Sharpe ratio with Lo (2002)
standard error, maximum drawdown and turnover, alongside buy-and-hold. The
pooled row is an equal-weight portfolio across tickers.

## 9. Reproducibility

* `data/snapshot/` pins the data; `provenance.json` records the git
  commit, R version, package version and data hashes of each run.
* Seeds are fixed (`seed` in the config; `ranger` uses a fixed seed).
* `Dockerfile` pins R 4.5.2 and a dated CRAN snapshot.
* CI runs `R CMD check`, the test suite and a smoke experiment on every
  push.

## 10. Compute requirements

The full experiment is embarrassingly parallel over (ticker, horizon)
tasks. On a 10-core laptop with 8-9 workers it takes about 40-60 minutes;
the dominant costs are the monthly random-forest and `auto.arima` refits.
No cluster is required. The `future` backend is configurable, so scaling
to hundreds of tickers or intraday data would be a one-line change to
`future::plan()` (for example `future.batchtools` on SLURM).

## 11. Limitations

* Single-asset time-series models only; no cross-sectional information.
* Transaction costs are a flat 5 bp; no market impact or borrow costs.
* Prediction intervals are Gaussian; the CRPS therefore penalises
  fat-tailed models that are correct about the mean.
* The Garman-Klass proxy excludes overnight variance, so models trained
  on it look biased against the squared-return proxy and vice versa.
* Multiple comparisons: with 7 models and 10 tickers some p-values below
  0.05 are expected by chance; the pooled results are the primary
  evidence.

## References

* Campbell, J. Y. & Thompson, S. B. (2008). Predicting excess stock returns out of sample. *Review of Financial Studies*.
* Corsi, F. (2009). A simple approximate long-memory model of realized volatility. *Journal of Financial Econometrics*.
* Diebold, F. X. & Mariano, R. S. (1995). Comparing predictive accuracy. *Journal of Business & Economic Statistics*.
* Garman, M. B. & Klass, M. J. (1980). On the estimation of security price volatilities from historical data. *Journal of Business*.
* Gneiting, T. & Raftery, A. E. (2007). Strictly proper scoring rules, prediction, and estimation. *JASA*.
* Harvey, D., Leybourne, S. & Newbold, P. (1997). Testing the equality of prediction mean squared errors. *International Journal of Forecasting*.
* Lo, A. W. (2002). The statistics of Sharpe ratios. *Financial Analysts Journal*.
* Patton, A. J. (2011). Volatility forecast comparison using imperfect volatility proxies. *Journal of Econometrics*.
* Pesaran, M. H. & Timmermann, A. (1992). A simple nonparametric test of predictive performance. *Journal of Business & Economic Statistics*.
* Welch, I. & Goyal, A. (2008). A comprehensive look at the empirical performance of equity premium prediction. *Review of Financial Studies*.
