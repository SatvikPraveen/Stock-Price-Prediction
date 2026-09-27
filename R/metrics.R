# ---- point-forecast losses ------------------------------------------------

#' Root mean squared error
#' @param actual,pred Numeric vectors.
#' @return A scalar.
#' @export
rmse <- function(actual, pred) sqrt(mean((actual - pred)^2))

#' Mean absolute error
#' @inheritParams rmse
#' @return A scalar.
#' @export
mae <- function(actual, pred) mean(abs(actual - pred))

#' Out-of-sample R-squared relative to a benchmark forecast
#'
#' Campbell & Thompson (2008): `1 - SSE(model) / SSE(benchmark)`. Positive
#' values mean the model beats the benchmark in mean squared error.
#'
#' @param actual,pred,bench Numeric vectors.
#' @return A scalar.
#' @export
oos_r2 <- function(actual, pred, bench) {
  1 - sum((actual - pred)^2) / sum((actual - bench)^2)
}

#' Directional accuracy (hit rate on the sign of the target)
#'
#' Observations where either the realised value or the forecast is exactly
#' zero are dropped.
#'
#' @inheritParams rmse
#' @return A scalar in `[0, 1]`.
#' @export
directional_accuracy <- function(actual, pred) {
  ok <- actual != 0 & pred != 0
  mean(sign(actual[ok]) == sign(pred[ok]))
}

# ---- probabilistic scores -------------------------------------------------

#' Continuous ranked probability score for a Gaussian predictive distribution
#'
#' Closed form from Gneiting & Raftery (2007). Lower is better; it is a
#' strictly proper scoring rule.
#'
#' @param actual Realised values.
#' @param mean,sd Predictive mean and standard deviation.
#' @return Vector of CRPS values.
#' @export
crps_normal <- function(actual, mean, sd) {
  z <- (actual - mean) / sd
  sd * (z * (2 * stats::pnorm(z) - 1) + 2 * stats::dnorm(z) - 1 / sqrt(pi))
}

#' Empirical coverage of central prediction intervals
#' @param actual Realised values.
#' @param lower,upper Interval bounds.
#' @return Scalar coverage rate.
#' @export
coverage <- function(actual, lower, upper) mean(actual >= lower & actual <= upper)

#' Winkler interval score
#'
#' Width of the interval plus a penalty of `2/alpha` times the distance by
#' which the realised value falls outside it (Winkler, 1972). Lower is better.
#'
#' @inheritParams coverage
#' @param alpha Nominal miscoverage (0.05 for a 95% interval).
#' @return Vector of scores.
#' @export
winkler <- function(actual, lower, upper, alpha = 0.05) {
  w <- upper - lower
  w + (2 / alpha) * pmax(lower - actual, 0) + (2 / alpha) * pmax(actual - upper, 0)
}

# ---- variance-forecast losses ---------------------------------------------

#' QLIKE loss for variance forecasts
#'
#' `proxy / forecast - log(proxy / forecast) - 1`. Together with MSE it is
#' one of the two losses robust to noise in the volatility proxy (Patton,
#' 2011). Lower is better.
#'
#' @param proxy Realised variance proxy.
#' @param forecast Variance forecast.
#' @return Vector of losses.
#' @export
qlike <- function(proxy, forecast) {
  r <- proxy / forecast
  r - log(r) - 1
}

# ---- formal tests ---------------------------------------------------------

#' Diebold-Mariano test of equal predictive accuracy
#'
#' Tests whether the mean loss differential `d = L(e1) - L(e2)` is zero,
#' using a long-run variance estimate with `h - 1` autocovariance terms
#' (rectangular kernel, as in Diebold & Mariano 1995) and the small-sample
#' correction of Harvey, Leybourne & Newbold (1997) with Student-t critical
#' values. If the rectangular estimate is not positive, a Bartlett kernel
#' with the same bandwidth is used instead.
#'
#' A negative statistic favours forecast 1.
#'
#' @param e1,e2 Forecast errors (`actual - forecast`) of the two competing
#'   forecasts, or, if `loss` is a function of one argument, the quantities
#'   it should be applied to.
#' @param h Forecast horizon (sets the autocovariance truncation).
#' @param loss `"squared"`, `"absolute"`, or a function mapping a vector to
#'   per-observation losses.
#' @param alternative `"two.sided"`, `"less"` (forecast 1 is better) or
#'   `"greater"`.
#' @return A list with `statistic`, `p_value`, `n`, `mean_diff`.
#' @export
dm_test <- function(e1, e2, h = 1, loss = c("squared", "absolute"),
                    alternative = c("two.sided", "less", "greater")) {
  alternative <- match.arg(alternative)
  if (is.function(loss)) {
    d <- loss(e1) - loss(e2)
  } else {
    loss <- match.arg(loss)
    d <- if (loss == "squared") e1^2 - e2^2 else abs(e1) - abs(e2)
  }
  d <- d[is.finite(d)]
  n <- length(d)
  if (n < 10) return(list(statistic = NA_real_, p_value = NA_real_, n = n,
                          mean_diff = mean(d)))
  dbar <- mean(d)
  lag_max <- max(h - 1, 0)
  gam <- stats::acf(d, lag.max = lag_max, type = "covariance", plot = FALSE,
                    demean = TRUE)$acf[, 1, 1]
  lrv <- gam[1] + 2 * sum(gam[-1])
  if (!is.finite(lrv) || lrv <= 0) {
    w <- 1 - seq_len(lag_max) / (lag_max + 1)
    lrv <- gam[1] + 2 * sum(w * gam[-1])
  }
  if (!is.finite(lrv) || lrv <= 0) {
    return(list(statistic = NA_real_, p_value = NA_real_, n = n, mean_diff = dbar))
  }
  stat <- dbar / sqrt(lrv / n)
  stat <- stat * sqrt((n + 1 - 2 * h + h * (h - 1) / n) / n)
  p <- switch(alternative,
    two.sided = 2 * stats::pt(-abs(stat), df = n - 1),
    less = stats::pt(stat, df = n - 1),
    greater = 1 - stats::pt(stat, df = n - 1)
  )
  list(statistic = stat, p_value = p, n = n, mean_diff = dbar)
}

#' Pesaran-Timmermann test of directional predictive ability
#'
#' Tests whether the sign of the forecast and the sign of the realisation
#' are independent (Pesaran & Timmermann, 1992). Under the null the
#' statistic is standard normal; the reported p-value is one-sided (the
#' alternative being positive directional skill).
#'
#' @inheritParams rmse
#' @return A list with `statistic`, `p_value`, `hit_rate`, `expected`, `n`.
#' @export
pt_test <- function(actual, pred) {
  ok <- is.finite(actual) & is.finite(pred) & actual != 0 & pred != 0
  y <- actual[ok] > 0
  x <- pred[ok] > 0
  n <- length(y)
  if (n < 10) return(list(statistic = NA_real_, p_value = NA_real_,
                          hit_rate = NA_real_, expected = NA_real_, n = n))
  p_hat <- mean(y == x)
  py <- mean(y)
  px <- mean(x)
  p_star <- py * px + (1 - py) * (1 - px)
  v_hat <- p_star * (1 - p_star) / n
  v_star <- (2 * py - 1)^2 * px * (1 - px) / n +
    (2 * px - 1)^2 * py * (1 - py) / n +
    4 * py * px * (1 - py) * (1 - px) / n^2
  denom <- v_hat - v_star
  if (!is.finite(denom) || denom <= 0) {
    return(list(statistic = NA_real_, p_value = NA_real_, hit_rate = p_hat,
                expected = p_star, n = n))
  }
  stat <- (p_hat - p_star) / sqrt(denom)
  list(statistic = stat, p_value = 1 - stats::pnorm(stat), hit_rate = p_hat,
       expected = p_star, n = n)
}

# ---- evaluation tables ----------------------------------------------------

common_sample <- function(fc, model, bench, task) {
  a <- fc[fc$model == model & fc$task == task, ]
  b <- fc[fc$model == bench & fc$task == task, ]
  key_a <- paste(a$ticker, a$origin_date)
  key_b <- paste(b$ticker, b$origin_date)
  if (task == "return") {
    ok_a <- is.finite(a$point)
    ok_b <- is.finite(b$point)
  } else {
    ok_a <- is.finite(a$var) & a$var > 0
    ok_b <- is.finite(b$var) & b$var > 0
  }
  keys <- intersect(key_a[ok_a], key_b[ok_b])
  a <- a[match(keys, key_a), ]
  b <- b[match(keys, key_b), ]
  list(model = a, bench = b)
}

evaluate_return_group <- function(a, b, h) {
  z <- stats::qnorm(0.975)
  lower <- a$point - z * a$sd
  upper <- a$point + z * a$sd
  has_sd <- is.finite(a$sd) & a$sd > 0
  dm <- dm_test(a$actual_ret - a$point, b$actual_ret - b$point, h = h)
  pt <- pt_test(a$actual_ret, a$point)
  data.frame(
    n = nrow(a),
    rmse = rmse(a$actual_ret, a$point),
    mae = mae(a$actual_ret, a$point),
    oos_r2 = oos_r2(a$actual_ret, a$point, b$point),
    dir_acc = directional_accuracy(a$actual_ret, a$point),
    pt_stat = pt$statistic,
    pt_p = pt$p_value,
    dm_stat = dm$statistic,
    dm_p = dm$p_value,
    crps = if (any(has_sd)) mean(crps_normal(a$actual_ret[has_sd], a$point[has_sd], a$sd[has_sd])) else NA_real_,
    coverage_95 = if (any(has_sd)) coverage(a$actual_ret[has_sd], lower[has_sd], upper[has_sd]) else NA_real_,
    winkler_95 = if (any(has_sd)) mean(winkler(a$actual_ret[has_sd], lower[has_sd], upper[has_sd])) else NA_real_,
    refits = sum(a$refit),
    mean_fit_secs = mean(a$fit_secs, na.rm = TRUE),
    errors = sum(!is.na(a$error))
  )
}

evaluate_vol_group <- function(a, b, h) {
  out <- data.frame(n = nrow(a))
  for (proxy in c("r2", "gk")) {
    y <- a[[paste0("actual_", proxy)]]
    ok <- is.finite(y) & y > 0
    ql <- qlike(y[ok], a$var[ok])
    ql_b <- qlike(y[ok], b$var[ok])
    dm_q <- dm_test(ql, ql_b, h = h, loss = function(v) v)
    dm_m <- dm_test(y[ok] - a$var[ok], y[ok] - b$var[ok], h = h)
    out[[paste0("qlike_", proxy)]] <- mean(ql)
    out[[paste0("mse_", proxy)]] <- mean((y[ok] - a$var[ok])^2)
    out[[paste0("dm_qlike_p_", proxy)]] <- dm_q$p_value
    out[[paste0("dm_mse_p_", proxy)]] <- dm_m$p_value
    out[[paste0("dm_qlike_stat_", proxy)]] <- dm_q$statistic
  }
  out$refits <- sum(a$refit)
  out$mean_fit_secs <- mean(a$fit_secs, na.rm = TRUE)
  out$errors <- sum(!is.na(a$error))
  out
}

#' Evaluate walk-forward forecasts against a benchmark
#'
#' Every model is scored on the sample of origins where both it and the
#' benchmark produced a finite forecast, so that comparisons are like for
#' like. Results are reported per ticker and pooled across tickers
#' (`ticker = "POOLED"`).
#'
#' @param fc Output of [walk_forward()] / [run_experiment()].
#' @param benchmarks Named list giving the benchmark model per task.
#' @return A `data.frame` of metrics with one row per
#'   (ticker, horizon, task, model).
#' @export
evaluate_forecasts <- function(fc, benchmarks = list(return = "naive_zero",
                                                     volatility = "hist_var")) {
  fc$ticker <- as.character(fc$ticker)
  groups <- unique(fc[, c("h", "task", "model")])
  tickers <- c(unique(fc$ticker), "POOLED")
  out <- list()
  for (g in seq_len(nrow(groups))) {
    h <- groups$h[g]
    task <- groups$task[g]
    model <- groups$model[g]
    bench <- benchmarks[[task]]
    if (is.null(bench) || !bench %in% fc$model) next
    sub <- fc[fc$h == h, ]
    for (tk in tickers) {
      s <- if (tk == "POOLED") sub else sub[sub$ticker == tk, ]
      cs <- common_sample(s, model, bench, task)
      if (nrow(cs$model) < 10) next
      row <- if (task == "return") evaluate_return_group(cs$model, cs$bench, h)
             else evaluate_vol_group(cs$model, cs$bench, h)
      out[[length(out) + 1]] <- cbind(
        data.frame(ticker = tk, h = h, task = task, model = model,
                   benchmark = bench, stringsAsFactors = FALSE),
        row
      )
    }
  }
  res <- do.call(rbind, out)
  rownames(res) <- NULL
  res
}
