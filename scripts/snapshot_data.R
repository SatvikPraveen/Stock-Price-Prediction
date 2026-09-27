#!/usr/bin/env Rscript
# Download the ticker universe from Yahoo Finance and pin it to data/snapshot/.
# Usage: Rscript scripts/snapshot_data.R [config/experiment.yml]
args <- commandArgs(trailingOnly = TRUE)
cfg_path <- if (length(args) >= 1) args[1] else "config/experiment.yml"
suppressPackageStartupMessages(pkgload::load_all(".", quiet = TRUE))
cfg <- read_config(cfg_path)
manifest <- snapshot_universe(cfg$tickers, from = cfg$from, cache_dir = cfg$cache_dir)
for (m in manifest) {
  cat(sprintf("%-6s %5d rows  %s .. %s  sha256:%s\n",
              m$ticker, m$rows, m$first_date, m$last_date, substr(m$sha256, 1, 12)))
}
