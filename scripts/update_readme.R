#!/usr/bin/env Rscript
# Regenerate the results section of README.md from results/latest so the
# numbers on GitHub are always the ones produced by the committed run.
# Usage: Rscript scripts/update_readme.R [results/latest]
args <- commandArgs(trailingOnly = TRUE)
rd <- if (length(args) >= 1) args[1] else "results/latest"

summ <- jsonlite::read_json(file.path(rd, "summary.json"))
cfg <- yaml::read_yaml(file.path(rd, "config.yml"))
ret <- read.csv(file.path(rd, "leaderboard_return.csv"))
vol <- read.csv(file.path(rd, "leaderboard_volatility.csv"))
strat <- read.csv(file.path(rd, "strategy.csv"))
drift <- read.csv(file.path(rd, "leaderboard_return_vs_drift.csv"))

fmt <- function(x, d = 4) formatC(x, digits = d, format = "f")
pval <- function(p) ifelse(is.na(p), "n/a", ifelse(p < 0.001, "<0.001", fmt(p, 3)))
md_table <- function(df) {
  hdr <- paste0("| ", paste(names(df), collapse = " | "), " |")
  sep <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
  rows <- apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  paste(c(hdr, sep, rows), collapse = "\n")
}

pr <- ret[ret$ticker == "POOLED" & ret$h == 1, ]
pr <- pr[order(pr$rmse), ]
pd <- drift[drift$ticker == "POOLED" & drift$h == 1, ]
pr$dm_p_drift <- pd$dm_p[match(pr$model, pd$model)]
pr$oos_r2_drift <- pd$oos_r2[match(pr$model, pd$model)]
ret_tbl <- data.frame(
  Model = pr$model,
  RMSE = fmt(pr$rmse, 5),
  `OOS R²` = fmt(pr$oos_r2, 4),
  `Dir. acc.` = fmt(pr$dir_acc, 3),
  `PT p` = pval(pr$pt_p),
  `DM p vs RW` = pval(pr$dm_p),
  `OOS R² vs drift` = fmt(pr$oos_r2_drift, 4),
  `DM p vs drift` = pval(pr$dm_p_drift),
  CRPS = fmt(pr$crps, 5),
  `95% cov.` = fmt(pr$coverage_95, 3),
  check.names = FALSE
)
ret_tbl$`Dir. acc.`[ret_tbl$Model == "naive_zero"] <- "–"
ret_tbl[ret_tbl$Model == "hist_mean", c("OOS R² vs drift", "DM p vs drift")] <- "–"

pv <- vol[vol$ticker == "POOLED" & vol$h == 1, ]
pv <- pv[order(pv$qlike_r2), ]
vol_tbl <- data.frame(
  Model = pv$model,
  `QLIKE (r²)` = fmt(pv$qlike_r2, 4),
  `DM p (r²)` = pval(pv$dm_qlike_p_r2),
  `QLIKE (GK)` = fmt(pv$qlike_gk, 4),
  `DM p (GK)` = pval(pv$dm_qlike_p_gk),
  check.names = FALSE
)

ps <- strat[strat$ticker == "POOLED" & strat$rule == "long_flat", ]
ps <- ps[order(-ps$sharpe), ]
strat_tbl <- data.frame(
  Model = ps$model,
  `Ann. return` = fmt(ps$ann_return, 3),
  `Ann. vol` = fmt(ps$ann_vol, 3),
  Sharpe = ifelse(is.na(ps$sharpe), "–", paste0(fmt(ps$sharpe, 2), " ± ", fmt(ps$sharpe_se, 2))),
  `Max DD` = fmt(ps$max_drawdown, 3),
  check.names = FALSE
)

h1 <- pr[pr$model != "naive_zero", ]
beat <- h1$model[!is.na(h1$dm_p) & h1$dm_p < 0.05 & h1$oos_r2 > 0]
worse <- h1$model[!is.na(h1$dm_p) & h1$dm_p < 0.05 & h1$oos_r2 < 0]
hd <- h1[h1$model != "hist_mean", ]
beat_drift <- hd$model[!is.na(hd$dm_p_drift) & hd$dm_p_drift < 0.05 & hd$oos_r2_drift > 0]
vbest <- pv[pv$model != "hist_var", ][1, ]
n_sig_vol <- sum(pv$model != "hist_var" & !is.na(pv$dm_qlike_p_r2) & pv$dm_qlike_p_r2 < 0.05 &
                   pv$qlike_r2 < pv$qlike_r2[pv$model == "hist_var"])

section <- paste0(
  "Run `", summ$run_id, "` at commit `", summ$git_sha, "`: ", summ$n_tickers,
  " tickers, forecast origins every trading day from ", summ$oos_start, " to ", summ$oos_end,
  ", parameters refit every ", cfg$refit_every, " days, ",
  format(summ$n_forecasts, big.mark = ","), " forecasts. All tables are pooled across tickers at h = 1;",
  " per-ticker tables, h = 5 and figures are in [`results/latest/`](results/latest/) and the",
  " [rendered report](reports/report.Rmd).\n\n",
  "**Headline.** ", length(beat), " of ", nrow(h1), " return models beat the random walk at the 5% level",
  if (length(beat)) paste0(" (", paste(beat, collapse = ", "), ")") else "",
  "; ", length(worse), if (length(worse) == 1) " is" else " are", " significantly worse",
  if (length(worse)) paste0(" (", paste(worse, collapse = ", "), ")") else "",
  ". The best out-of-sample R² is ", fmt(max(h1$oos_r2), 4), " (", h1$model[which.max(h1$oos_r2)], ").",
  " Against the random walk **with drift** (the expanding-window mean, `hist_mean`), ",
  length(beat_drift), " of ", nrow(hd), " models are significantly better",
  if (length(beat_drift)) paste0(" (", paste(beat_drift, collapse = ", "), ")") else "", ".",
  " For volatility, ", n_sig_vol, " of ", nrow(pv) - 1, " models beat the rolling-variance benchmark",
  " at the 5% level; the best is **", vbest$model, "** (QLIKE ", fmt(vbest$qlike_r2, 3), " vs ",
  fmt(pv$qlike_r2[pv$model == "hist_var"], 3), ", DM p ", pval(vbest$dm_qlike_p_r2), ").\n\n",
  "#### Return forecasts (h = 1, pooled)\n\n", md_table(ret_tbl), "\n\n",
  "`OOS R²` is relative to the zero-return random walk (Campbell-Thompson) or to the random walk",
  " with drift; `DM p` is the two-sided Diebold-Mariano p-value with the HLN correction; `PT p` is",
  " the Pesaran-Timmermann directional test (undefined when a model's forecast sign never changes);",
  " `CRPS` scores the Gaussian predictive distribution.\n\n",
  "#### Variance forecasts (h = 1, pooled)\n\n", md_table(vol_tbl), "\n\n",
  "QLIKE is reported against squared returns (r², unbiased proxy) and Garman-Klass realised variance",
  " (GK, precise but excludes overnight moves); DM tests are against `hist_var`.\n\n",
  "#### Trading backtest (long/flat, ", cfg$cost_bps, " bp costs, equal-weight, h = 1)\n\n",
  md_table(strat_tbl), "\n\n",
  "Sharpe ratios are annualised with Lo (2002) standard errors. `hist_mean` is almost always long,",
  " so it tracks buy-and-hold minus costs; `naive_zero` never trades.\n\n",
  "![Cumulative squared-error difference vs. random walk](results/latest/figures/cumulative_sse_h1.png)\n"
)

readme <- readLines("README.md")
start <- grep("<!-- results:start -->", readme)
end <- grep("<!-- results:end -->", readme)
stopifnot(length(start) == 1, length(end) == 1, start < end)
new <- c(readme[1:start], "", strsplit(section, "\n")[[1]], "", readme[end:length(readme)])
writeLines(new, "README.md")
cat("README results section updated from", rd, "\n")
