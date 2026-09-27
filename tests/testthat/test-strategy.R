make_fc <- function(points, rets, ticker = "T", model = "m") {
  n <- length(points)
  data.frame(
    ticker = ticker, model = model, task = "return", h = 1,
    origin_date = as.Date("2020-01-01") + seq_len(n) - 1,
    target_date = as.Date("2020-01-02") + seq_len(n) - 1,
    point = points, sd = 0.01, var = NA_real_, actual_ret = rets,
    actual_r2 = rets^2, actual_gk = rets^2, refit = FALSE, fit_secs = NA,
    error = NA_character_, stringsAsFactors = FALSE
  )
}

test_that("strategy_returns applies positions and charges costs on turnover", {
  fc <- make_fc(points = c(0.01, 0.02, -0.01, -0.02, 0.01),
                rets = c(0.03, -0.01, 0.02, -0.04, 0.01))
  sr <- strategy_returns(fc, rule = "long_flat", cost_bps = 10)
  expect_equal(sr$position, c(1, 1, 0, 0, 1))
  # costs at t1 (enter), t3 (exit), t5 (re-enter)
  expect_equal(sr$cost, c(0.001, 0, 0.001, 0, 0.001))
  expect_equal(sr$strategy_ret, c(0.03 - 0.001, -0.01, -0.001, 0, 0.01 - 0.001))
  ls <- strategy_returns(fc, rule = "long_short", cost_bps = 0)
  expect_equal(ls$strategy_ret, c(0.03, -0.01, -0.02, 0.04, 0.01))
})

test_that("perf_stats and drawdown are correct on a simple path", {
  r <- c(0.1, -0.2, 0.05)
  ps <- perf_stats(r)
  expect_equal(ps$total_return, expm1(sum(r)))
  expect_equal(ps$max_drawdown, 1 - exp(-0.2))
  expect_equal(ps$sharpe, mean(r) / sd(r) * sqrt(252))
})

test_that("backtest_strategy adds buy-and-hold and pooled rows", {
  fc <- rbind(make_fc(rnorm(60, 0, 0.01), rnorm(60, 0, 0.02), "A"),
              make_fc(rnorm(60, 0, 0.01), rnorm(60, 0, 0.02), "B"))
  bt <- backtest_strategy(fc, cost_bps = 5)
  expect_setequal(unique(bt$model), c("m", "buy_hold"))
  expect_setequal(unique(bt$ticker), c("A", "B", "POOLED"))
  expect_equal(bt$rule[1], "long_flat")
})

test_that("a perfect-foresight strategy dominates buy-and-hold", {
  set.seed(4)
  rets <- rnorm(500, 0, 0.02)
  fc <- make_fc(points = rets, rets = rets)
  bt <- backtest_strategy(fc, cost_bps = 0)
  expect_gt(bt$sharpe[bt$model == "m" & bt$ticker == "T"],
            bt$sharpe[bt$model == "buy_hold" & bt$ticker == "T"])
})
