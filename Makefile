# Common entry points. Run `make help` for a summary.
R       ?= Rscript
CONFIG  ?= config/experiment.yml

.PHONY: help deps install document test check lint data quick experiment report app docker docker-run clean

help:
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

deps: ## Install R package dependencies (uses pak if available)
	$(R) -e 'if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak"); pak::local_install_deps(dependencies = TRUE)'

install: document ## Install the package into the R library (needed for parallel workers)
	R CMD INSTALL --no-multiarch --no-docs .

document: ## Regenerate NAMESPACE and man/ from roxygen comments
	$(R) -e 'roxygen2::roxygenise()'

test: ## Run the testthat suite
	$(R) -e 'pkgload::load_all(quiet = TRUE); testthat::test_dir("tests/testthat", reporter = "progress", stop_on_failure = TRUE)'

check: ## R CMD check
	$(R) -e 'rcmdcheck::rcmdcheck(args = c("--no-manual", "--as-cran"), error_on = "warning")'

lint: ## Static analysis with lintr
	$(R) -e 'lintr::lint_package()'

data: ## Refresh the pinned data snapshot from Yahoo Finance
	$(R) scripts/snapshot_data.R $(CONFIG)

quick: install ## ~1-minute smoke experiment (2 tickers, weekly origins)
	$(R) scripts/run_experiment.R config/quick.yml --run-id quick

experiment: install ## Full walk-forward experiment (~20-30 min on 8 cores)
	$(R) scripts/run_experiment.R $(CONFIG)

report: ## Render reports/report.html from results/latest
	$(R) scripts/render_report.R results/latest

app: ## Launch the Shiny dashboard locally
	$(R) -e 'shiny::runApp("shiny_app", launch.browser = TRUE)'

docker: ## Build the reproducible Docker image
	docker build -t stockcast .

docker-run: ## Run the full experiment inside Docker, writing to ./results
	docker run --rm -v "$$PWD/results:/work/results" stockcast make experiment

clean: ## Remove rendered reports and check artefacts
	rm -rf reports/report.html reports/report_files *.Rcheck stockcast_*.tar.gz
