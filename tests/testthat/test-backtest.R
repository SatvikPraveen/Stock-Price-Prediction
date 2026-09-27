test_that("walk_forward produces aligned, strictly out-of-sample rows", {
  feat <- make_features(synthetic_prices(400))
  models <- get_models(c("naive_zero", "hist_mean", "hist_var"))
  fc <- walk_forward(feat, models, h = 2, initial = 300, step = 5,
                     refit_every = 10, ticker = "SYN")
  origins <- seq(300, 398, by = 5)
  expect_equal(nrow(fc), 3 * length(origins))
  expect_equal(unique(fc$h), 2)
  one <- fc[fc$model == "naive_zero", ]
  expect_equal(one$origin_date, feat$date[origins])
  expect_equal(one$target_date, feat$date[origins + 2])
  expect_equal(one$actual_ret, feat$logp[origins + 2] - feat$logp[origins])
  expect_true(all(one$point == 0))
  expect_true(all(is.na(fc$error)))
  # refit flags: first origin plus every refit_every-th origin distance
  expect_true(one$refit[1])
  expect_equal(sum(one$refit), length(unique(cumsum(c(0, diff(origins))) %/% 10)))
})

test_that("walk_forward records model errors instead of aborting", {
  feat <- make_features(synthetic_prices(320))
  broken <- new_model("broken", "return",
                      fit = function(train, h) stop("boom"),
                      predict = function(fit, train, h) list(point = 1, sd = 1))
  fc <- walk_forward(feat, list(broken), h = 1, initial = 300, step = 1)
  expect_true(all(grepl("boom", fc$error)))
  expect_true(all(is.na(fc$point)))
})

test_that("sliding window limits the training sample seen by the model", {
  feat <- make_features(synthetic_prices(350))
  seen <- integer(0)
  spy <- new_model(
    "spy", "return",
    fit = function(train, h) {
      seen <<- c(seen, nrow(train))
      NULL
    },
    predict = function(fit, train, h) list(point = 0, sd = 1)
  )
  walk_forward(feat, list(spy), h = 1, initial = 300, step = 1, refit_every = 1,
               window = "sliding", window_size = 200)
  expect_true(all(seen == 200))
})

test_that("hist_mean beats naive_zero on a series with a strong drift", {
  x <- synthetic_prices(900, seed = 9)
  # inject a large, persistent drift so the mean is genuinely predictable
  adj <- as.numeric(x$Adjusted) * exp(0.01 * seq_len(900))
  x$Adjusted <- adj
  x$Close <- adj
  x$Open <- adj
  x$High <- adj * 1.01
  x$Low <- adj * 0.99
  feat <- make_features(x)
  fc <- walk_forward(feat, get_models(c("naive_zero", "hist_mean")),
                     h = 1, initial = 500, step = 1)
  ev <- evaluate_forecasts(fc)
  hm <- ev[ev$model == "hist_mean" & ev$ticker == "POOLED", ]
  expect_gt(hm$oos_r2, 0.5)
  expect_lt(hm$dm_p, 0.01)
  expect_gt(hm$dir_acc, 0.8)
})

test_that("evaluate_forecasts returns per-ticker and pooled rows for both tasks", {
  feat <- make_features(synthetic_prices(450))
  models <- get_models(c("naive_zero", "hist_mean", "hist_var", "ewma"))
  fc <- rbind(
    walk_forward(feat, models, h = 1, initial = 400, step = 1, ticker = "A"),
    walk_forward(feat, models, h = 1, initial = 400, step = 1, ticker = "B")
  )
  ev <- evaluate_forecasts(fc)
  expect_setequal(unique(ev$ticker), c("A", "B", "POOLED"))
  expect_setequal(unique(ev$task), c("return", "volatility"))
  expect_equal(ev$n[ev$ticker == "POOLED"][1], 2 * 50)
  vol <- ev[ev$task == "volatility", ]
  expect_true(all(is.finite(vol$qlike_r2)))
  expect_true(all(c("qlike_gk", "mse_r2", "dm_qlike_p_r2") %in% names(vol)))
})

test_that("read_config fills defaults from YAML", {
  path <- withr::local_tempfile(fileext = ".yml")
  writeLines(c("tickers: [AAA, BBB]", "horizons: [1]", "step: 5"), path)
  cfg <- read_config(path)
  expect_equal(cfg$tickers, c("AAA", "BBB"))
  expect_equal(cfg$step, 5)
  expect_equal(cfg$refit_every, default_config()$refit_every)
  expect_type(cfg$horizons, "integer")
})
