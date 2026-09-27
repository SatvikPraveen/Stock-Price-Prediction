#!/usr/bin/env Rscript
# Run a walk-forward experiment and summarise it.
# Usage: Rscript scripts/run_experiment.R [config/experiment.yml] [--run-id ID] [--no-summary]
args <- commandArgs(trailingOnly = TRUE)
cfg_path <- "config/experiment.yml"
run_id <- NULL
do_summary <- TRUE
i <- 1
while (i <= length(args)) {
  if (args[i] == "--run-id") { run_id <- args[i + 1]; i <- i + 2; next }
  if (args[i] == "--no-summary") { do_summary <- FALSE; i <- i + 1; next }
  cfg_path <- args[i]; i <- i + 1
}
suppressPackageStartupMessages(pkgload::load_all(".", quiet = TRUE))
cfg <- read_config(cfg_path)
t0 <- Sys.time()
run_dir <- run_experiment(cfg, run_id = run_id)
cat(sprintf("Experiment finished in %.1f minutes: %s\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins")), run_dir))
if (do_summary) {
  res <- summarise_run(run_dir, latest_dir = file.path(cfg$results_dir, "latest"),
                       cost_bps = cfg$cost_bps)
  pooled <- res$return[res$return$ticker == "POOLED", ]
  cat("\nPooled return-forecast leaderboard:\n")
  print(pooled[order(pooled$h, pooled$rmse),
               c("h", "model", "rmse", "oos_r2", "dir_acc", "dm_p", "crps", "coverage_95")],
        row.names = FALSE, digits = 4)
  vol <- res$volatility[res$volatility$ticker == "POOLED", ]
  cat("\nPooled volatility-forecast leaderboard:\n")
  print(vol[order(vol$h, vol$qlike_r2),
            c("h", "model", "qlike_r2", "qlike_gk", "dm_qlike_p_r2", "dm_qlike_p_gk")],
        row.names = FALSE, digits = 4)
}
