#!/usr/bin/env Rscript
# Render reports/report.Rmd against results/latest (or a given run directory).
# Usage: Rscript scripts/render_report.R [results/latest]
args <- commandArgs(trailingOnly = TRUE)
results_dir <- if (length(args) >= 1) args[1] else "results/latest"
if (!rmarkdown::pandoc_available()) stop("pandoc is required to render the report")
out <- rmarkdown::render(
  "reports/report.Rmd",
  params = list(results_dir = normalizePath(results_dir)),
  output_file = "report.html", quiet = TRUE
)
cat("Report written to", out, "\n")
