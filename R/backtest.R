#' Rolling-origin (walk-forward) out-of-sample evaluation
#'
#' For each forecast origin `t` in `seq(initial, n - h, by = step)` the model
#' sees only rows `1..t` (expanding window) or `(t - window_size + 1)..t`
#' (sliding window). Parameters are re-estimated every `refit_every`
#' origins; in between, `predict()` updates the model state with the new
#' observations but holds parameters fixed. Realised targets are attached
#' from rows `t+1 .. t+h`.
#'
#' Errors thrown by a model at a given origin are caught, recorded in the
#' `error` column and yield `NA` forecasts, so one fragile fit cannot abort
#' a multi-hour run.
#'
#' @param feat Feature `data.frame` from [make_features()].
#' @param models A list of `stockcast_model` objects (see [get_models()]).
#' @param h Forecast horizon in trading days.
#' @param initial Number of observations in the first training window.
#' @param step Distance between consecutive origins (1 = every day).
#' @param refit_every Re-estimate parameters every this many origins.
#' @param window `"expanding"` or `"sliding"`.
#' @param window_size Window length when `window = "sliding"`.
#' @param ticker Label stored in the output.
#' @param progress Optional function called with the model name after each
#'   model completes.
#' @return A `data.frame` with one row per (model, origin) containing the
#'   forecast (`point`, `sd`, `var`), the realised targets (`actual_ret`,
#'   `actual_r2`, `actual_gk`), whether the origin triggered a refit, the
#'   fit time in seconds, and any error message.
#' @export
walk_forward <- function(feat, models, h = 1, initial = 1000, step = 1,
                         refit_every = 21, window = c("expanding", "sliding"),
                         window_size = initial, ticker = "series",
                         progress = NULL) {
  window <- match.arg(window)
  n <- nrow(feat)
  if (n <= initial + h) {
    stop("Not enough observations: n = ", n, ", initial = ", initial, ", h = ", h)
  }
  origins <- seq(initial, n - h, by = step)
  y_ret <- forward_return(feat, h)
  y_var <- forward_variance(feat, h)

  results <- vector("list", length(models))
  for (m in seq_along(models)) {
    model <- models[[m]]
    fit <- NULL
    last_fit <- -Inf
    fit_ok <- FALSE
    rows <- vector("list", length(origins))

    for (j in seq_along(origins)) {
      i <- origins[j]
      start <- if (window == "sliding") max(1L, i - window_size + 1L) else 1L
      train <- feat[start:i, , drop = FALSE]

      refit <- FALSE
      err <- NA_character_
      secs <- NA_real_
      if (!fit_ok || (i - last_fit) >= refit_every) {
        t0 <- proc.time()[["elapsed"]]
        fit <- tryCatch(model$fit(train, h), error = function(e) {
          err <<- paste0("fit: ", conditionMessage(e))
          NULL
        })
        secs <- proc.time()[["elapsed"]] - t0
        fit_ok <- is.na(err)
        last_fit <- i
        refit <- TRUE
      }

      pred <- if (is.na(err)) {
        tryCatch(model$predict(fit, train, h), error = function(e) {
          err <<- paste0("predict: ", conditionMessage(e))
          NULL
        })
      }
      point <- if (!is.null(pred$point)) pred$point else NA_real_
      psd <- if (!is.null(pred$sd)) pred$sd else NA_real_
      pvar <- if (!is.null(pred$var)) pred$var else NA_real_

      rows[[j]] <- data.frame(
        ticker = ticker, model = model$name, task = model$task, h = h,
        origin_date = feat$date[i], target_date = feat$date[i + h],
        point = as.numeric(point), sd = as.numeric(psd), var = as.numeric(pvar),
        actual_ret = y_ret[i], actual_r2 = y_var$r2[i], actual_gk = y_var$gk[i],
        refit = refit, fit_secs = secs, error = err,
        stringsAsFactors = FALSE
      )
    }
    results[[m]] <- do.call(rbind, rows)
    if (is.function(progress)) progress(model$name)
  }
  out <- do.call(rbind, results)
  rownames(out) <- NULL
  out
}

#' Default experiment configuration
#'
#' @return A list with the same structure as `config/experiment.yml`.
#' @export
default_config <- function() {
  list(
    name = "default",
    tickers = c("AAPL", "MSFT", "AMZN", "GOOGL", "NVDA",
                "JPM", "XOM", "JNJ", "PG", "SPY"),
    from = "2010-01-01",
    horizons = c(1, 5),
    initial = 1000,
    step = 1,
    refit_every = 21,
    window = "expanding",
    models = NULL,
    cost_bps = 5,
    workers = max(1L, min(8L, future::availableCores() - 1L)),
    seed = 20240101,
    cache_dir = "data/snapshot",
    results_dir = "results"
  )
}

#' Read an experiment configuration from YAML, filling defaults
#'
#' @param path Path to a YAML file.
#' @return A configuration list.
#' @export
read_config <- function(path) {
  cfg <- default_config()
  user <- yaml::read_yaml(path)
  cfg[names(user)] <- user
  cfg$horizons <- as.integer(cfg$horizons)
  cfg
}

git_sha <- function() {
  sha <- tryCatch(
    system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE),
    error = function(e) NA_character_, warning = function(w) NA_character_
  )
  if (length(sha) == 0) NA_character_ else sha[1]
}

#' Run a full experiment from a configuration
#'
#' Tickers and horizons are distributed across `future` workers; models run
#' sequentially inside each task. Forecasts, timings, the resolved
#' configuration, the data manifest, the git commit and `sessionInfo()` are
#' written to `results/runs/<run_id>/`.
#'
#' @param cfg Configuration list (see [default_config()] / [read_config()]).
#' @param run_id Optional run identifier; defaults to a timestamp.
#' @param quiet Suppress progress messages.
#' @return The run directory (invisibly). The forecasts are also returned as
#'   attribute `"forecasts"`.
#' @export
run_experiment <- function(cfg = default_config(), run_id = NULL, quiet = FALSE) {
  run_id <- run_id %||% format(Sys.time(), "%Y%m%d-%H%M%S")
  run_dir <- file.path(cfg$results_dir, "runs", run_id)
  dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)

  prices <- get_prices(cfg$tickers, from = cfg$from, cache_dir = cfg$cache_dir)
  models <- get_models(cfg$models)
  tasks <- expand.grid(ticker = cfg$tickers, h = cfg$horizons,
                       stringsAsFactors = FALSE)

  if (!quiet) {
    message(sprintf("Run %s: %d tickers x %d horizons x %d models, step = %d, refit_every = %d, workers = %d",
                    run_id, length(cfg$tickers), length(cfg$horizons),
                    length(models), cfg$step, cfg$refit_every, cfg$workers))
  }

  old_plan <- future::plan()
  on.exit(future::plan(old_plan), add = TRUE)
  workers <- cfg$workers
  if (workers > 1 && !package_installed("stockcast")) {
    warning("stockcast is not installed in .libPaths(); parallel workers cannot ",
            "load it. Falling back to a single process. Run `make install` ",
            "(R CMD INSTALL .) to enable parallel runs.", call. = FALSE, immediate. = TRUE)
    workers <- 1L
  }
  if (workers > 1) {
    future::plan(future::multisession, workers = workers)
  } else {
    future::plan(future::sequential)
  }

  run_one <- function(ticker, h) {
    set.seed(cfg$seed)
    feat <- make_features(prices[[ticker]])
    t0 <- proc.time()[["elapsed"]]
    fc <- walk_forward(feat, models, h = h, initial = cfg$initial,
                       step = cfg$step, refit_every = cfg$refit_every,
                       window = cfg$window, ticker = ticker)
    fc$task_secs <- proc.time()[["elapsed"]] - t0
    fc
  }
  pieces <- furrr::future_map2(
    tasks$ticker, tasks$h, run_one,
    .options = furrr::furrr_options(seed = TRUE, packages = "stockcast")
  )
  forecasts <- do.call(rbind, pieces)

  saveRDS(forecasts, file.path(run_dir, "forecasts.rds"))
  write.csv(forecasts, file.path(run_dir, "forecasts.csv"), row.names = FALSE)
  yaml::write_yaml(cfg, file.path(run_dir, "config.yml"))
  jsonlite::write_json(
    list(run_id = run_id, git_sha = git_sha(),
         finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
         r_version = R.version.string,
         stockcast_version = as.character(packageVersion("stockcast")),
         manifest = read_manifest(cfg$cache_dir)),
    file.path(run_dir, "provenance.json"), auto_unbox = TRUE, pretty = TRUE
  )
  writeLines(utils::capture.output(sessionInfo()), file.path(run_dir, "sessionInfo.txt"))

  if (!quiet) message("Forecasts written to ", run_dir)
  structure(invisible(run_dir), forecasts = forecasts)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# TRUE if the package is installed in a library (as opposed to only loaded
# from source with pkgload::load_all()), which is what background workers need.
package_installed <- function(pkg) {
  any(dir.exists(file.path(.libPaths(), pkg)))
}
