test_that("garman_klass is zero for a flat day and positive for a range", {
  expect_equal(garman_klass(100, 100, 100, 100), 0)
  expect_gt(garman_klass(100, 102, 98, 101), 0)
})

test_that("features contain the documented columns and no NA at the end", {
  feat <- make_features(synthetic_prices(300))
  expect_true(all(stockcast:::FEATURE_COLS %in% names(feat)))
  expect_equal(nrow(feat), 300)
  expect_false(anyNA(feat[300, stockcast:::FEATURE_COLS]))
})

test_that("features are causal: truncating the future does not change the past", {
  x <- synthetic_prices(400)
  full <- make_features(x)
  short <- make_features(x[1:350, ])
  cols <- c("ret", "rv_gk", stockcast:::FEATURE_COLS)
  expect_equal(full[1:350, cols], short[, cols], tolerance = 1e-12)
})

test_that("lagged returns are exact shifts of ret", {
  feat <- make_features(synthetic_prices(200))
  expect_equal(feat$ret_lag_1[3:200], feat$ret[2:199])
  expect_equal(feat$ret_lag_5[10:200], feat$ret[5:195])
})

test_that("forward_return and forward_variance align to the future window", {
  feat <- make_features(synthetic_prices(150))
  y1 <- forward_return(feat, 1)
  expect_equal(y1[10], feat$logp[11] - feat$logp[10])
  expect_true(is.na(y1[150]))
  y5 <- forward_return(feat, 5)
  expect_equal(y5[20], sum(feat$ret[21:25]))
  v <- forward_variance(feat, 3)
  expect_equal(v$r2[30], sum(feat$ret[31:33]^2))
  expect_equal(v$gk[30], sum(feat$rv_gk[31:33]))
  expect_true(all(is.na(v$r2[148:150])))
})
