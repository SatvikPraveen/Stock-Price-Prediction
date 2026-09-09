test_that("fetch_stock_data() returns AAPL OHLCV data when Yahoo Finance is reachable", {
  stock_data <- fetch_stock_data()

  skip_if(is.null(stock_data), "Yahoo Finance is unreachable; skipping live-data test")

  expect_s3_class(stock_data, "xts")
  expect_true(nrow(stock_data) > 0)

  expected_cols <- c(
    "AAPL.Open", "AAPL.High", "AAPL.Low",
    "AAPL.Close", "AAPL.Volume", "AAPL.Adjusted"
  )
  expect_true(all(expected_cols %in% colnames(stock_data)))
})

test_that("train_model() fits a linear model with the expected coefficients", {
  dates <- as.Date("2024-01-01") + 0:9
  set.seed(42)
  open_prices  <- 100 + seq(0, 9) + rnorm(10, sd = 1)
  high_prices  <- open_prices + abs(rnorm(10, mean = 5, sd = 2))
  low_prices   <- open_prices - abs(rnorm(10, mean = 5, sd = 2))
  close_prices <- (open_prices + high_prices + low_prices) / 3 + rnorm(10, sd = 0.5)

  synthetic_data <- xts::xts(
    data.frame(
      AAPL.Open = open_prices,
      AAPL.High = high_prices,
      AAPL.Low  = low_prices,
      AAPL.Close = close_prices,
      AAPL.Volume = rep(1000000, 10),
      AAPL.Adjusted = close_prices
    ),
    order.by = dates
  )

  model <- train_model(synthetic_data)

  expect_s3_class(model, "lm")
  expect_setequal(
    names(coef(model)),
    c("(Intercept)", "OpenPrice", "HighPrice", "LowPrice")
  )
  expect_true(all(is.finite(coef(model))))
})

test_that("train_model() returns NULL for missing or empty data", {
  expect_null(train_model(NULL))

  empty_data <- xts::xts(
    data.frame(
      AAPL.Open = numeric(0), AAPL.High = numeric(0),
      AAPL.Low = numeric(0), AAPL.Close = numeric(0)
    ),
    order.by = as.Date(character(0))
  )
  expect_null(train_model(empty_data))
})
