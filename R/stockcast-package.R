#' stockcast: walk-forward evaluation of equity return and volatility forecasts
#'
#' The package is organised around five layers:
#'
#' 1. **Data** (`get_prices()`, `snapshot_universe()`): download daily OHLCV
#'    data from Yahoo Finance and pin it to a hashed on-disk snapshot so that
#'    every experiment is reproducible bit-for-bit.
#' 2. **Features** (`make_features()`): strictly lagged predictors (no
#'    look-ahead), including Garman-Klass realised variance from OHLC.
#' 3. **Models** (`model_registry()`): a uniform `fit()` / `predict()`
#'    interface for return and volatility forecasters, with periodic refits.
#' 4. **Evaluation** (`walk_forward()`, `evaluate_forecasts()`,
#'    `dm_test()`, `pt_test()`): rolling-origin out-of-sample evaluation with
#'    proper scoring rules and formal tests against a random-walk benchmark.
#' 5. **Economics** (`backtest_strategy()`): cost-aware trading backtest.
#'
#' @keywords internal
#' @importFrom stats sd var lm predict coef residuals na.omit pnorm qnorm
#'   dnorm pt setNames acf median
#' @importFrom utils read.csv write.csv head tail packageVersion sessionInfo
#' @importFrom ggplot2 .data
"_PACKAGE"

# Feature column names produced by make_features(); kept here so that models
# and tests agree on the exact predictor set.
FEATURE_COLS <- c(
  paste0("ret_lag_", 1:5),
  "ret_5", "ret_21", "mom_63",
  "vol_21", "rv_5", "rv_21",
  "rsi_14", "macd_hist", "bb_pctb", "hl_range", "vol_z"
)
