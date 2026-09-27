#' Define a forecasting model for the registry
#'
#' A model is a pair of closures with a uniform interface:
#'
#' * `fit(train, h)` receives the feature `data.frame` for all days up to
#'   and including the forecast origin, and the horizon `h`. It returns an
#'   arbitrary fitted object (or `NULL`).
#' * `predict(fit, train, h)` receives that object plus the (possibly
#'   longer) training data at the current origin. For `task = "return"` it
#'   returns `list(point = , sd = )` for the h-day cumulative log return;
#'   for `task = "volatility"` it returns `list(var = )`, the forecast
#'   variance of the h-day cumulative log return.
#'
#' Between refits the fitted parameters are held fixed and only the state
#' (filtered values, latest feature row) is updated with new data. This is
#' the standard "estimate every k days, forecast every day" design used in
#' the forecasting literature and keeps a daily walk-forward tractable.
#'
#' @param name Short unique identifier.
#' @param task `"return"` or `"volatility"`.
#' @param fit,predict Closures as described above.
#' @param description One-line description used in reports.
#' @param family Model family label used for grouping in reports.
#' @param path Logical: can `predict()` be called with horizons `1..h` from
#'   a fit made with horizon `h` (used to draw forecast paths in the app)?
#' @return An object of class `stockcast_model`.
#' @export
new_model <- function(name, task, fit, predict, description = name,
                      family = "other", path = TRUE) {
  stopifnot(task %in% c("return", "volatility"))
  structure(
    list(name = name, task = task, fit = fit, predict = predict,
         description = description, family = family, path = path),
    class = "stockcast_model"
  )
}

#' @export
print.stockcast_model <- function(x, ...) {
  cat(sprintf("<stockcast_model> %s [%s]: %s\n", x$name, x$task, x$description))
  invisible(x)
}

# ---- helpers ---------------------------------------------------------------

feature_matrix <- function(train) {
  as.matrix(train[, FEATURE_COLS, drop = FALSE])
}

# Supervised design for ML models: rows whose h-day forward return is known.
supervised_design <- function(train, h) {
  y <- forward_return(train, h)
  x <- feature_matrix(train)
  ok <- stats::complete.cases(x) & !is.na(y)
  list(x = x[ok, , drop = FALSE], y = y[ok], n = sum(ok))
}

last_feature_row <- function(train) {
  x <- feature_matrix(train)
  x[nrow(x), , drop = FALSE]
}

# Historical volatility used to attach a predictive sd to mean-only models.
hist_sd <- function(train, h, n = 252) {
  r <- tail(train$ret[!is.na(train$ret)], n)
  stats::sd(r) * sqrt(h)
}

# Blocked (contiguous) fold ids so that cross-validation inside glmnet does
# not leak future information into the past via random folds.
blocked_folds <- function(n, k = 5) {
  ceiling(seq_len(n) / n * k)
}

sd_from_interval <- function(lower, upper, level = 95) {
  z <- stats::qnorm(1 - (1 - level / 100) / 2)
  as.numeric((upper - lower) / (2 * z))
}

# ---- return models ---------------------------------------------------------

model_naive_zero <- function() {
  new_model(
    name = "naive_zero", task = "return", family = "benchmark",
    description = "Random walk: zero expected return, historical 252-day sd",
    fit = function(train, h) NULL,
    predict = function(fit, train, h) list(point = 0, sd = hist_sd(train, h))
  )
}

model_hist_mean <- function() {
  new_model(
    name = "hist_mean", task = "return", family = "benchmark",
    description = "Expanding-window mean return (random walk with drift)",
    fit = function(train, h) NULL,
    predict = function(fit, train, h) {
      list(point = mean(train$ret, na.rm = TRUE) * h, sd = hist_sd(train, h))
    }
  )
}

model_arima <- function() {
  new_model(
    name = "arima", task = "return", family = "statistical",
    description = "auto.arima on log price (non-seasonal), refit periodically",
    fit = function(train, h) {
      forecast::auto.arima(train$logp, seasonal = FALSE, stepwise = TRUE,
                           approximation = TRUE)
    },
    predict = function(fit, train, h) {
      refit <- forecast::Arima(train$logp, model = fit)
      fc <- forecast::forecast(refit, h = h, level = 95)
      last <- tail(train$logp, 1)
      list(point = as.numeric(fc$mean[h]) - last,
           sd = sd_from_interval(fc$lower[h], fc$upper[h]))
    }
  )
}

model_ets <- function() {
  new_model(
    name = "ets", task = "return", family = "statistical",
    description = "ETS (additive error, damped additive trend) on log price",
    fit = function(train, h) {
      forecast::ets(train$logp, model = "AAN", damped = TRUE)
    },
    predict = function(fit, train, h) {
      refit <- forecast::ets(train$logp, model = fit, use.initial.values = TRUE)
      fc <- forecast::forecast(refit, h = h, level = 95)
      last <- tail(train$logp, 1)
      list(point = as.numeric(fc$mean[h]) - last,
           sd = sd_from_interval(fc$lower[h], fc$upper[h]))
    }
  )
}

model_stlf <- function() {
  new_model(
    name = "stlf", task = "return", family = "statistical",
    description = "STL decomposition (period 252) + ETS on log price; reproduces the original notebook model",
    fit = function(train, h) {
      y <- stats::ts(train$logp, frequency = 252)
      forecast::stlm(y, s.window = "periodic", method = "ets", etsmodel = "ANN")
    },
    predict = function(fit, train, h) {
      y <- stats::ts(train$logp, frequency = 252)
      refit <- forecast::stlm(y, s.window = "periodic", model = fit)
      fc <- forecast::forecast(refit, h = h, level = 95)
      last <- tail(train$logp, 1)
      list(point = as.numeric(fc$mean[h]) - last,
           sd = sd_from_interval(fc$lower[h], fc$upper[h]))
    }
  )
}

model_glmnet <- function(alpha = 0.5) {
  new_model(
    name = "elastic_net", task = "return", family = "machine learning", path = FALSE,
    description = "Elastic net on lagged returns and technical features (blocked 5-fold CV)",
    fit = function(train, h) {
      d <- supervised_design(train, h)
      if (d$n < 100) return(NULL)
      cv <- glmnet::cv.glmnet(d$x, d$y, alpha = alpha, standardize = TRUE,
                              foldid = blocked_folds(d$n, 5))
      list(cv = cv, sd = sqrt(cv$cvm[cv$index["min", 1]]))
    },
    predict = function(fit, train, h) {
      if (is.null(fit)) return(list(point = NA_real_, sd = NA_real_))
      x <- last_feature_row(train)
      if (any(is.na(x))) return(list(point = NA_real_, sd = NA_real_))
      p <- as.numeric(stats::predict(fit$cv, newx = x, s = "lambda.min"))
      list(point = p, sd = fit$sd)
    }
  )
}

model_ranger <- function(num_trees = 500) {
  new_model(
    name = "random_forest", task = "return", family = "machine learning", path = FALSE,
    description = "Random forest on lagged returns and technical features (OOB sd)",
    fit = function(train, h) {
      d <- supervised_design(train, h)
      if (d$n < 100) return(NULL)
      df <- data.frame(y = d$y, d$x)
      rf <- ranger::ranger(y ~ ., data = df, num.trees = num_trees,
                           min.node.size = 20, seed = 1L, num.threads = 1L)
      list(rf = rf, sd = sqrt(rf$prediction.error))
    },
    predict = function(fit, train, h) {
      if (is.null(fit)) return(list(point = NA_real_, sd = NA_real_))
      x <- last_feature_row(train)
      if (any(is.na(x))) return(list(point = NA_real_, sd = NA_real_))
      p <- stats::predict(fit$rf, data = as.data.frame(x), num.threads = 1L)$predictions
      list(point = as.numeric(p), sd = fit$sd)
    }
  )
}

garch_spec <- function(fixed = NULL) {
  rugarch::ugarchspec(
    variance.model = list(model = "sGARCH", garchOrder = c(1, 1)),
    mean.model = list(armaOrder = c(0, 0), include.mean = TRUE),
    distribution.model = "std",
    fixed.pars = fixed
  )
}

fit_garch <- function(train) {
  r <- train$ret[!is.na(train$ret)]
  # rugarch warns when the Hessian is singular; the point estimates are
  # still usable for forecasting, so we do not surface that warning.
  fit <- suppressWarnings(rugarch::ugarchfit(garch_spec(), r, solver = "hybrid"))
  if (fit@fit$convergence != 0) return(NULL)
  as.list(rugarch::coef(fit))
}

forecast_garch <- function(pars, train, h) {
  r <- train$ret[!is.na(train$ret)]
  spec <- garch_spec(fixed = pars)
  fc <- rugarch::ugarchforecast(spec, data = r, n.ahead = h)
  mu <- as.numeric(rugarch::fitted(fc))
  sig <- as.numeric(rugarch::sigma(fc))
  list(point = sum(mu), sd = sqrt(sum(sig^2)), var = sum(sig^2))
}

model_garch_mean <- function() {
  new_model(
    name = "arma_garch", task = "return", family = "statistical",
    description = "Constant mean + GARCH(1,1) with Student-t innovations (mean forecast)",
    fit = function(train, h) fit_garch(train),
    predict = function(fit, train, h) {
      if (is.null(fit)) return(list(point = NA_real_, sd = NA_real_))
      f <- forecast_garch(fit, train, h)
      list(point = f$point, sd = f$sd)
    }
  )
}

# ---- volatility models -----------------------------------------------------

model_hist_var <- function(n = 21) {
  new_model(
    name = "hist_var", task = "volatility", family = "benchmark",
    description = sprintf("Rolling %d-day sample variance of returns", n),
    fit = function(train, h) NULL,
    predict = function(fit, train, h) {
      r <- tail(train$ret[!is.na(train$ret)], n)
      list(var = stats::var(r) * h)
    }
  )
}

model_ewma <- function(lambda = 0.94) {
  new_model(
    name = "ewma", task = "volatility", family = "benchmark",
    description = sprintf("RiskMetrics EWMA of squared returns (lambda = %.2f)", lambda),
    fit = function(train, h) NULL,
    predict = function(fit, train, h) {
      r <- train$ret[!is.na(train$ret)]
      s2 <- stats::var(head(r, 21))
      for (x in r) s2 <- lambda * s2 + (1 - lambda) * x^2
      list(var = s2 * h)
    }
  )
}

model_garch_var <- function() {
  new_model(
    name = "garch11", task = "volatility", family = "statistical",
    description = "GARCH(1,1) with Student-t innovations (variance forecast)",
    fit = function(train, h) fit_garch(train),
    predict = function(fit, train, h) {
      if (is.null(fit)) return(list(var = NA_real_))
      list(var = forecast_garch(fit, train, h)$var)
    }
  )
}

# HAR-RV (Corsi, 2009): regress future variance on daily, weekly and monthly
# averages of realised variance. `target` selects what is regressed on the
# HAR components: Garman-Klass RV ("gk") or squared returns ("r2").
har_design <- function(train, h, target = c("gk", "r2")) {
  target <- match.arg(target)
  y <- forward_variance(train, h)[[target]]
  x <- data.frame(rv_d = train$rv_gk, rv_w = train$rv_5, rv_m = train$rv_21)
  ok <- stats::complete.cases(x) & !is.na(y)
  list(y = y[ok], x = x[ok, ], x_last = x[nrow(x), ], n = sum(ok))
}

model_har <- function(target = c("gk", "r2")) {
  target <- match.arg(target)
  new_model(
    name = paste0("har_", target), task = "volatility", family = "statistical",
    description = sprintf(
      "HAR-RV on Garman-Klass components, target = %s",
      if (target == "gk") "future Garman-Klass variance" else "future squared returns"
    ),
    fit = function(train, h) {
      d <- har_design(train, h, target)
      if (d$n < 100) return(NULL)
      stats::lm(y ~ rv_d + rv_w + rv_m, data = data.frame(y = d$y, d$x))
    },
    predict = function(fit, train, h) {
      if (is.null(fit)) return(list(var = NA_real_))
      d <- har_design(train, h, target)
      if (any(is.na(d$x_last))) return(list(var = NA_real_))
      p <- as.numeric(stats::predict(fit, newdata = d$x_last))
      list(var = max(p, 1e-8))
    }
  )
}

# ---- registry --------------------------------------------------------------

#' The model registry
#'
#' @return A named list of `stockcast_model` objects.
#' @export
model_registry <- function() {
  models <- list(
    model_naive_zero(), model_hist_mean(), model_arima(), model_ets(),
    model_stlf(), model_glmnet(), model_ranger(), model_garch_mean(),
    model_hist_var(), model_ewma(), model_garch_var(),
    model_har("gk"), model_har("r2")
  )
  setNames(models, vapply(models, `[[`, "", "name"))
}

#' List registered models
#'
#' @return A `data.frame` with one row per model.
#' @export
list_models <- function() {
  reg <- model_registry()
  data.frame(
    name = vapply(reg, `[[`, "", "name"),
    task = vapply(reg, `[[`, "", "task"),
    family = vapply(reg, `[[`, "", "family"),
    description = vapply(reg, `[[`, "", "description"),
    row.names = NULL
  )
}

#' Retrieve models by name
#'
#' @param names Character vector of model names; `NULL` returns all.
#' @return A named list of `stockcast_model` objects.
#' @export
get_models <- function(names = NULL) {
  reg <- model_registry()
  if (is.null(names)) return(reg)
  unknown <- setdiff(names, names(reg))
  if (length(unknown) > 0) {
    stop("Unknown model(s): ", paste(unknown, collapse = ", "))
  }
  reg[names]
}
