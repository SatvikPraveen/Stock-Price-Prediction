test_that("point losses match hand computations", {
  a <- c(1, 2, 3); p <- c(1, 1, 5)
  expect_equal(rmse(a, p), sqrt(mean(c(0, 1, 4))))
  expect_equal(mae(a, p), 1)
  expect_equal(oos_r2(a, p, rep(0, 3)), 1 - 5 / 14)
  expect_equal(directional_accuracy(c(1, -1, 2, 0), c(2, 1, 1, 5)), 2 / 3)
})

test_that("crps_normal is proper: the true distribution scores best on average", {
  set.seed(7)
  y <- rnorm(20000, 0, 1)
  good <- mean(crps_normal(y, 0, 1))
  wide <- mean(crps_normal(y, 0, 2))
  shifted <- mean(crps_normal(y, 0.5, 1))
  expect_lt(good, wide)
  expect_lt(good, shifted)
  # closed form at the mean: sd * (2/sqrt(2*pi) - 1/sqrt(pi))
  expect_equal(crps_normal(0, 0, 1), 2 / sqrt(2 * pi) - 1 / sqrt(pi))
})

test_that("coverage and winkler behave", {
  expect_equal(coverage(c(0, 5, 10), c(-1, 6, 9), c(1, 7, 11)), 2 / 3)
  expect_equal(winkler(0, -1, 1), 2)
  expect_equal(winkler(2, -1, 1, alpha = 0.05), 2 + 40)
})

test_that("qlike is zero at a perfect forecast and positive otherwise", {
  expect_equal(qlike(2, 2), 0)
  expect_gt(qlike(2, 1), 0)
  expect_gt(qlike(1, 2), 0)
})

test_that("dm_test matches forecast::dm.test for h = 1 and h = 4", {
  set.seed(11)
  e1 <- rnorm(250); e2 <- rnorm(250, sd = 1.15)
  for (h in c(1, 4)) {
    mine <- dm_test(e1, e2, h = h)
    ref <- forecast::dm.test(e1, e2, h = h, power = 2)
    expect_equal(mine$statistic, unname(ref$statistic), tolerance = 1e-8)
    expect_equal(mine$p_value, unname(ref$p.value), tolerance = 1e-8)
  }
  mine_abs <- dm_test(e1, e2, h = 2, loss = "absolute", alternative = "less")
  ref_abs <- forecast::dm.test(e1, e2, h = 2, power = 1, alternative = "less")
  expect_equal(mine_abs$p_value, unname(ref_abs$p.value), tolerance = 1e-8)
})

test_that("dm_test accepts a custom loss and handles degenerate input", {
  set.seed(2)
  l1 <- rexp(100); l2 <- rexp(100)
  out <- dm_test(l1, l2, loss = function(v) v)
  expect_equal(out$mean_diff, mean(l1 - l2))
  expect_true(is.na(dm_test(rnorm(5), rnorm(5))$statistic))
})

test_that("pt_test detects directional skill and not its absence", {
  set.seed(3)
  actual <- rnorm(2000)
  skilled <- actual + rnorm(2000, sd = 1.5)
  unskilled <- rnorm(2000)
  expect_lt(pt_test(actual, skilled)$p_value, 0.001)
  expect_gt(pt_test(actual, unskilled)$p_value, 0.01)
  expect_equal(pt_test(actual, skilled)$hit_rate,
               directional_accuracy(actual, skilled))
})
