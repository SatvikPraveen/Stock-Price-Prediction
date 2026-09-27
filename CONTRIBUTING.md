# Contributing

Thanks for your interest in improving this project. It is organised as an R
package (`stockcast`) plus an experiment pipeline and a Shiny dashboard.

## Development setup

```bash
git clone https://github.com/SatvikPraveen/Stock-Price-Prediction.git
cd Stock-Price-Prediction
make deps      # install R dependencies (uses pak)
make install   # install the package so parallel workers can load it
make test      # run the testthat suite (no network needed)
make quick     # ~5-minute smoke experiment on the pinned snapshot
```

`make help` lists every target. `Rscript -e 'roxygen2::roxygenise()'` (or
`make document`) regenerates `NAMESPACE` and `man/` after editing roxygen
comments.

## Adding a model

1. Write a constructor in `R/models.R` that returns `new_model(...)` with
   `fit(train, h)` and `predict(fit, train, h)` closures. Return models
   must return `list(point, sd)`, volatility models `list(var)`. Between
   refits `predict()` must hold parameters fixed and only update state.
2. Register it in `model_registry()`.
3. The generic test in `tests/testthat/test-models.R` will automatically
   check that it fits and predicts on synthetic data.
4. Run `make quick` and inspect `results/runs/quick/leaderboard_*.csv`.

## Adding a metric or test

Put the function in `R/metrics.R` with a roxygen block and a citation, add
a hand-computed or reference-implementation test in
`tests/testthat/test-metrics.R`, and wire it into `evaluate_return_group()`
or `evaluate_vol_group()`.

## Pull requests

* Keep the data snapshot untouched unless the PR is specifically about
  refreshing it (`make data`); refreshing changes every result.
* CI must pass: `R CMD check`, `lintr`, the test suite and the smoke
  experiment.
* If a change affects results, re-run `make experiment` and commit the
  updated `results/latest/` together with the code so that the README's
  numbers stay tied to the commit that produced them.
* Follow the tidyverse style guide; `make lint` will tell you if you don't.

## Reporting issues

Please include the R version, `sessionInfo()`, the config file used and,
if relevant, the `provenance.json` of the run.
