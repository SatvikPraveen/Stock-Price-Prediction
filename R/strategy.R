#' Cost-aware trading backtest driven by one-day-ahead return forecasts
#'
#' Positions are set at the close of the origin day from the sign of the
#' forecast and earn the next day's log return. Transaction costs of
#' `cost_bps` basis points are charged on every unit of turnover
#' `|pos_t - pos_{t-1}|`. Only `h = 1` forecasts are used so that positions
#' are non-overlapping.
#'
#' @param fc Forecast table (return task, any set of models/tickers).
#' @param rule `"long_flat"` (long when forecast > 0, else cash) or
#'   `"long_short"`.
#' @param cost_bps One-way transaction cost in basis points.
#' @return A `data.frame` of daily strategy returns with columns `ticker`,
#'   `model`, `date`, `position`, `ret`, `strategy_ret`, `cost`.
#' @export
strategy_returns <- function(fc, rule = c("long_flat", "long_short"),
                             cost_bps = 5) {
  rule <- match.arg(rule)
  fc <- fc[fc$task == "return" & fc$h == 1 & is.finite(fc$point), ]
  fc <- fc[order(fc$ticker, fc$model, fc$origin_date), ]
  cost <- cost_bps / 1e4
  pieces <- split(fc, list(fc$ticker, fc$model), drop = TRUE)
  out <- lapply(pieces, function(d) {
    pos <- if (rule == "long_flat") as.numeric(d$point > 0) else sign(d$point)
    turnover <- abs(diff(c(0, pos)))
    data.frame(
      ticker = d$ticker, model = d$model, date = d$target_date,
      position = pos, ret = d$actual_ret,
      strategy_ret = pos * d$actual_ret - cost * turnover,
      cost = cost * turnover, stringsAsFactors = FALSE
    )
  })
  res <- do.call(rbind, out)
  rownames(res) <- NULL
  res
}

# Append buy-and-hold rows (realised return once per ticker and date) to a
# strategy_returns() table.
with_buy_hold <- function(sr) {
  bh <- unique(sr[, c("ticker", "date", "ret")])
  bh$model <- "buy_hold"
  bh$position <- 1
  bh$strategy_ret <- bh$ret
  bh$cost <- 0
  rbind(sr, bh[, names(sr)])
}

max_drawdown <- function(log_returns) {
  eq <- exp(cumsum(log_returns))
  peak <- cummax(eq)
  max(1 - eq / peak)
}

#' Performance statistics for a vector of daily log returns
#'
#' Sharpe ratios are annualised with `sqrt(252)`; the standard error of the
#' Sharpe ratio follows Lo (2002) under i.i.d. returns.
#'
#' @param r Daily log returns.
#' @return A one-row `data.frame`.
#' @export
perf_stats <- function(r) {
  r <- r[is.finite(r)]
  n <- length(r)
  mu <- mean(r)
  s <- stats::sd(r)
  sr <- if (s > 0) mu / s * sqrt(252) else NA_real_
  data.frame(
    n_days = n,
    ann_return = mu * 252,
    ann_vol = s * sqrt(252),
    sharpe = sr,
    sharpe_se = if (is.finite(sr)) sqrt((1 + sr^2 / 2) / (n / 252)) else NA_real_,
    max_drawdown = max_drawdown(r),
    total_return = expm1(sum(r))
  )
}

#' Summarise strategy performance per ticker and model, with buy-and-hold
#'
#' @inheritParams strategy_returns
#' @return A `data.frame` with one row per (ticker, model), including
#'   `buy_hold` rows and pooled equal-weight rows (`ticker = "POOLED"`).
#' @export
backtest_strategy <- function(fc, rule = c("long_flat", "long_short"),
                              cost_bps = 5) {
  rule <- match.arg(rule)
  sr <- strategy_returns(fc, rule = rule, cost_bps = cost_bps)
  if (nrow(sr) == 0) return(data.frame())

  all <- with_buy_hold(sr)

  per <- split(all, list(all$ticker, all$model), drop = TRUE)
  rows <- lapply(per, function(d) {
    cbind(data.frame(ticker = d$ticker[1], model = d$model[1],
                     stringsAsFactors = FALSE),
          perf_stats(d$strategy_ret),
          turnover_per_year = sum(abs(diff(c(0, d$position)))) / (nrow(d) / 252))
  })
  # pooled: equal-weight average across tickers per date
  pooled <- lapply(split(all, all$model), function(d) {
    daily <- tapply(d$strategy_ret, d$date, mean)
    cbind(data.frame(ticker = "POOLED", model = d$model[1], stringsAsFactors = FALSE),
          perf_stats(as.numeric(daily)),
          turnover_per_year = NA_real_)
  })
  res <- do.call(rbind, c(rows, pooled))
  res$rule <- rule
  res$cost_bps <- cost_bps
  rownames(res) <- NULL
  res
}
