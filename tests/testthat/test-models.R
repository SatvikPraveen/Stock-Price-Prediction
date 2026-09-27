test_that("registry is well formed", {
  reg <- model_registry()
  expect_true(all(vapply(reg, inherits, TRUE, "stockcast_model")))
  expect_equal(names(reg), unname(vapply(reg, `[[`, "", "name")))
  lm <- list_models()
  expect_setequal(lm$task, c("return", "volatility"))
  expect_error(get_models("no_such_model"), "Unknown model")
  expect_length(get_models(c("naive_zero", "ewma")), 2)
})

test_that("every model fits and predicts on synthetic data with the right shape", {
  feat <- make_features(synthetic_prices(1200))
  train <- feat[1:1100, ]
  for (m in model_registry()) {
    fit <- m$fit(train, 1)
    p <- m$predict(fit, train, 1)
    if (m$task == "return") {
      expect_true(is.finite(p$point), info = m$name)
      expect_true(is.finite(p$sd) && p$sd > 0, info = m$name)
      expect_lt(abs(p$point), 0.2)
    } else {
      expect_true(is.finite(p$var) && p$var > 0, info = m$name)
      expect_lt(p$var, 0.01)
    }
  }
})

test_that("benchmark forecasts are what they claim to be", {
  feat <- make_features(synthetic_prices(600))
  train <- feat[1:500, ]
  nz <- model_registry()$naive_zero
  expect_equal(nz$predict(NULL, train, 1)$point, 0)
  expect_equal(nz$predict(NULL, train, 4)$sd,
               sd(tail(train$ret[!is.na(train$ret)], 252)) * 2)
  hv <- model_registry()$hist_var
  expect_equal(hv$predict(NULL, train, 1)$var,
               var(tail(train$ret[!is.na(train$ret)], 21)))
})

test_that("garch variance forecast is close to a known persistent process", {
  feat <- make_features(synthetic_prices(2000, seed = 5))
  g <- model_registry()$garch11
  fit <- g$fit(feat, 1)
  expect_false(is.null(fit))
  expect_gt(fit$alpha1 + fit$beta1, 0.85)
  expect_lt(fit$alpha1 + fit$beta1, 1)
})

test_that("ML models return NA gracefully when training data is too short", {
  feat <- make_features(synthetic_prices(150))
  en <- model_registry()$elastic_net
  expect_null(en$fit(feat[1:120, ], 1))
  expect_true(is.na(en$predict(NULL, feat[1:120, ], 1)$point))
})
