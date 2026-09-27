#' Cumulative squared-error difference against the benchmark
#'
#' The running sum of `e_bench^2 - e_model^2`. An upward-sloping line means
#' the model has been beating the benchmark over that period; this is the
#' standard "fluctuation" diagnostic that shows *when* predictive gains
#' occur rather than only whether they exist on average.
#'
#' @param fc Forecast table (return task).
#' @param benchmark Benchmark model name.
#' @param h Horizon to plot.
#' @return A `data.frame` with columns `ticker`, `model`, `date`, `cum_diff`.
#' @export
cumulative_sse_diff <- function(fc, benchmark = "naive_zero", h = 1) {
  fc <- fc[fc$task == "return" & fc$h == h, ]
  models <- setdiff(unique(fc$model), benchmark)
  out <- list()
  for (tk in unique(fc$ticker)) {
    for (m in models) {
      cs <- common_sample(fc[fc$ticker == tk, ], m, benchmark, "return")
      if (nrow(cs$model) == 0) next
      d <- (cs$bench$actual_ret - cs$bench$point)^2 -
        (cs$model$actual_ret - cs$model$point)^2
      out[[length(out) + 1]] <- data.frame(
        ticker = tk, model = m, date = cs$model$target_date,
        cum_diff = cumsum(d), stringsAsFactors = FALSE
      )
    }
  }
  res <- do.call(rbind, out)
  rownames(res) <- NULL
  res
}

theme_report <- function() {
  ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(legend.position = "bottom",
                   panel.grid.minor = ggplot2::element_blank())
}

plot_cum_sse <- function(cd) {
  ggplot2::ggplot(cd, ggplot2::aes(x = .data$date, y = .data$cum_diff,
                                   colour = .data$model)) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey50") +
    ggplot2::geom_line(linewidth = 0.4) +
    ggplot2::facet_wrap(~ ticker, scales = "free_y") +
    ggplot2::labs(
      title = "Cumulative squared-error difference vs. random walk (h = 1)",
      subtitle = "Above zero: model has beaten the zero-return benchmark up to that date",
      x = NULL, y = expression(sum(e[RW]^2 - e[model]^2)), colour = NULL
    ) +
    theme_report()
}

plot_leaderboard <- function(ev, metric, title, lower_better = TRUE) {
  d <- ev[ev$ticker == "POOLED", ]
  d$model <- stats::reorder(d$model, if (lower_better) -d[[metric]] else d[[metric]])
  ggplot2::ggplot(d, ggplot2::aes(x = .data$model, y = .data[[metric]],
                                  fill = .data$model == .data$benchmark)) +
    ggplot2::geom_col(show.legend = FALSE) +
    ggplot2::scale_fill_manual(values = c(`TRUE` = "grey40", `FALSE` = "steelblue")) +
    ggplot2::facet_wrap(~ h, labeller = ggplot2::label_both, scales = "free_x") +
    ggplot2::coord_flip() +
    ggplot2::labs(title = title, x = NULL, y = metric) +
    theme_report()
}

plot_equity <- function(sr) {
  daily <- stats::aggregate(strategy_ret ~ model + date, data = sr, FUN = mean)
  daily <- daily[order(daily$model, daily$date), ]
  daily$equity <- stats::ave(daily$strategy_ret, daily$model,
                             FUN = function(x) exp(cumsum(x)))
  ggplot2::ggplot(daily, ggplot2::aes(x = .data$date, y = .data$equity,
                                      colour = .data$model)) +
    ggplot2::geom_line(linewidth = 0.4) +
    ggplot2::scale_y_log10() +
    ggplot2::labs(
      title = "Equal-weight long/flat strategy equity (net of costs) vs. buy-and-hold",
      x = NULL, y = "Growth of $1 (log scale)", colour = NULL
    ) +
    theme_report()
}

#' Summarise a run: evaluation tables, strategy backtest and figures
#'
#' Writes `leaderboard_return.csv`, `leaderboard_volatility.csv`,
#' `strategy.csv`, `cumulative_sse.csv`, `summary.json` and a `figures/`
#' folder into the run directory, and optionally mirrors them into
#' `results/latest/`.
#'
#' @param run_dir Directory produced by [run_experiment()].
#' @param latest_dir If not `NULL`, copy the outputs there as well.
#' @param cost_bps Transaction cost for the strategy backtest.
#' @return A list with the evaluation tables (invisibly).
#' @export
summarise_run <- function(run_dir, latest_dir = "results/latest", cost_bps = 5) {
  fc <- readRDS(file.path(run_dir, "forecasts.rds"))
  ev <- evaluate_forecasts(fc)
  ev_ret <- ev[ev$task == "return", ]
  ev_vol <- ev[ev$task == "volatility", ]
  ev_ret <- ev_ret[, colSums(!is.na(ev_ret)) > 0]
  ev_vol <- ev_vol[, colSums(!is.na(ev_vol)) > 0]

  strat <- backtest_strategy(fc, rule = "long_flat", cost_bps = cost_bps)
  strat_ls <- backtest_strategy(fc, rule = "long_short", cost_bps = cost_bps)
  strat_all <- rbind(strat, strat_ls)
  cd <- cumulative_sse_diff(fc, h = 1)

  write.csv(ev_ret, file.path(run_dir, "leaderboard_return.csv"), row.names = FALSE)
  write.csv(ev_vol, file.path(run_dir, "leaderboard_volatility.csv"), row.names = FALSE)
  write.csv(strat_all, file.path(run_dir, "strategy.csv"), row.names = FALSE)
  write.csv(cd, file.path(run_dir, "cumulative_sse.csv"), row.names = FALSE)

  fig_dir <- file.path(run_dir, "figures")
  dir.create(fig_dir, showWarnings = FALSE)
  save_fig <- function(p, name, w = 10, h = 6) {
    ggplot2::ggsave(file.path(fig_dir, name), p, width = w, height = h, dpi = 150,
                    bg = "white")
  }
  if (nrow(cd) > 0) save_fig(plot_cum_sse(cd), "cumulative_sse_h1.png", 11, 7)
  if (nrow(ev_ret) > 0) {
    save_fig(plot_leaderboard(ev_ret, "rmse", "Pooled RMSE of h-day return forecasts"),
             "leaderboard_rmse.png", 9, 5)
    save_fig(plot_leaderboard(ev_ret, "crps", "Pooled CRPS (Gaussian predictive distribution)"),
             "leaderboard_crps.png", 9, 5)
  }
  if (nrow(ev_vol) > 0) {
    save_fig(plot_leaderboard(ev_vol, "qlike_r2",
                              "Pooled QLIKE of variance forecasts (squared-return proxy)"),
             "leaderboard_qlike.png", 9, 5)
  }
  sr <- strategy_returns(fc, rule = "long_flat", cost_bps = cost_bps)
  if (nrow(sr) > 0) {
    save_fig(plot_equity(with_buy_hold(sr)), "equity_curves.png", 10, 6)
  }

  prov <- jsonlite::read_json(file.path(run_dir, "provenance.json"))
  pooled_ret <- ev_ret[ev_ret$ticker == "POOLED" & ev_ret$h == 1, ]
  summary <- list(
    run_id = basename(run_dir),
    git_sha = prov$git_sha,
    finished_at = prov$finished_at,
    n_tickers = length(unique(fc$ticker)),
    tickers = unique(fc$ticker),
    horizons = sort(unique(fc$h)),
    n_forecasts = nrow(fc),
    oos_start = format(min(fc$origin_date)),
    oos_end = format(max(fc$target_date)),
    best_return_model_h1 = if (nrow(pooled_ret)) pooled_ret$model[which.min(pooled_ret$rmse)] else NA,
    models_beating_rw_h1_p05 = if (nrow(pooled_ret)) {
      sig <- !is.na(pooled_ret$dm_p) & pooled_ret$dm_p < 0.05 & pooled_ret$oos_r2 > 0
      pooled_ret$model[sig]
    } else {
      character(0)
    }
  )
  jsonlite::write_json(summary, file.path(run_dir, "summary.json"),
                       auto_unbox = TRUE, pretty = TRUE)

  if (!is.null(latest_dir)) {
    dir.create(latest_dir, recursive = TRUE, showWarnings = FALSE)
    unlink(list.files(latest_dir, full.names = TRUE), recursive = TRUE)
    files <- c("leaderboard_return.csv", "leaderboard_volatility.csv", "strategy.csv",
               "cumulative_sse.csv", "summary.json", "config.yml", "provenance.json",
               "sessionInfo.txt")
    file.copy(file.path(run_dir, files), latest_dir, overwrite = TRUE)
    dir.create(file.path(latest_dir, "figures"), showWarnings = FALSE)
    file.copy(list.files(fig_dir, full.names = TRUE), file.path(latest_dir, "figures"),
              overwrite = TRUE)
  }
  invisible(list(return = ev_ret, volatility = ev_vol, strategy = strat_all,
                 cumulative = cd, summary = summary))
}
