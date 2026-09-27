#' Garman-Klass daily variance estimator
#'
#' Uses the intraday open/high/low/close range and is roughly eight times
#' more efficient than squared close-to-close returns as a variance proxy
#' (Garman & Klass, 1980). Because it only uses same-day prices it is
#' unaffected by stock splits.
#'
#' @param open,high,low,close Numeric vectors of daily prices.
#' @return Numeric vector of daily variance estimates (in log-return units).
#' @export
garman_klass <- function(open, high, low, close) {
  0.5 * log(high / low)^2 - (2 * log(2) - 1) * log(close / open)^2
}

roll_sum <- function(x, n) {
  zoo::rollapplyr(x, n, sum, fill = NA, na.rm = FALSE)
}

roll_mean <- function(x, n) {
  zoo::rollapplyr(x, n, mean, fill = NA, na.rm = FALSE)
}

roll_sd <- function(x, n) {
  zoo::rollapplyr(x, n, stats::sd, fill = NA, na.rm = FALSE)
}

#' Build a strictly lagged feature matrix from daily OHLCV prices
#'
#' Every feature in row `t` is a function of information available at the
#' close of day `t` only. Forecast targets (returns over `t+1 .. t+h`) are
#' constructed by [walk_forward()], never here, which is what guarantees
#' the absence of look-ahead.
#'
#' Returns are log returns on the *adjusted* close (dividend- and
#' split-adjusted); realised variance uses unadjusted OHLC via
#' [garman_klass()].
#'
#' @param prices An `xts` object with Open/High/Low/Close/Volume/Adjusted.
#' @return A `data.frame` with columns `date`, `close`, `adj`, `logp`, `ret`,
#'   `rv_gk`, and the predictors listed in `FEATURE_COLS`. Leading rows
#'   contain `NA` where rolling windows are not yet full.
#' @export
make_features <- function(prices) {
  prices <- clean_prices(prices)
  d <- zoo::coredata(prices)
  n <- nrow(d)
  if (n < 70) stop("Need at least 70 observations to build features")

  adj <- as.numeric(d[, "Adjusted"])
  logp <- log(adj)
  ret <- c(NA, diff(logp))
  rv_gk <- garman_klass(d[, "Open"], d[, "High"], d[, "Low"], d[, "Close"])

  feat <- data.frame(
    date = zoo::index(prices),
    close = as.numeric(d[, "Close"]),
    adj = adj,
    logp = logp,
    ret = ret,
    rv_gk = as.numeric(rv_gk)
  )

  for (k in 1:5) {
    feat[[paste0("ret_lag_", k)]] <- c(rep(NA, k), head(ret, n - k))
  }
  feat$ret_5 <- roll_sum(ret, 5)
  feat$ret_21 <- roll_sum(ret, 21)
  feat$mom_63 <- roll_sum(ret, 63)
  feat$vol_21 <- roll_sd(ret, 21)
  feat$rv_5 <- roll_mean(feat$rv_gk, 5)
  feat$rv_21 <- roll_mean(feat$rv_gk, 21)

  # TTR indicators computed on the adjusted close; all are causal filters.
  feat$rsi_14 <- as.numeric(TTR::RSI(adj, n = 14))
  macd <- TTR::MACD(adj, nFast = 12, nSlow = 26, nSig = 9, percent = TRUE)
  feat$macd_hist <- as.numeric(macd[, "macd"] - macd[, "signal"])
  bb <- TTR::BBands(adj, n = 20, sd = 2)
  feat$bb_pctb <- as.numeric(bb[, "pctB"])
  feat$hl_range <- log(as.numeric(d[, "High"]) / as.numeric(d[, "Low"]))
  logv <- log1p(as.numeric(d[, "Volume"]))
  feat$vol_z <- (logv - roll_mean(logv, 21)) / roll_sd(logv, 21)

  rownames(feat) <- NULL
  feat
}

#' Realised h-day return target aligned to a feature matrix
#'
#' `y[i]` is the cumulative log return from the close of day `i` to the
#' close of day `i + h`; it is `NA` for the last `h` rows.
#'
#' @param feat Output of [make_features()].
#' @param h Horizon in trading days.
#' @return Numeric vector of length `nrow(feat)`.
#' @export
forward_return <- function(feat, h = 1) {
  n <- nrow(feat)
  y <- rep(NA_real_, n)
  if (n > h) y[1:(n - h)] <- feat$logp[(1 + h):n] - feat$logp[1:(n - h)]
  y
}

#' Realised h-day variance proxies aligned to a feature matrix
#'
#' Two proxies are returned: the sum of squared daily log returns over
#' `t+1 .. t+h` (conditionally unbiased for close-to-close variance but
#' noisy) and the sum of Garman-Klass daily variances (much less noisy, but
#' excludes the overnight return so is biased low as a proxy for
#' close-to-close variance).
#'
#' @inheritParams forward_return
#' @return A `data.frame` with columns `r2` and `gk`.
#' @export
forward_variance <- function(feat, h = 1) {
  n <- nrow(feat)
  r2 <- rep(NA_real_, n)
  gk <- rep(NA_real_, n)
  if (n > h) {
    cs_r2 <- cumsum(ifelse(is.na(feat$ret), 0, feat$ret^2))
    cs_gk <- cumsum(ifelse(is.na(feat$rv_gk), 0, feat$rv_gk))
    idx <- 1:(n - h)
    r2[idx] <- cs_r2[idx + h] - cs_r2[idx]
    gk[idx] <- cs_gk[idx + h] - cs_gk[idx]
  }
  data.frame(r2 = r2, gk = gk)
}
