# Exercises the Shiny app's server logic headlessly. Skipped under R CMD
# check (shiny_app/ is not part of the package tarball) and when the Shiny
# stack is not installed.
app_dir <- Find(dir.exists, c("../../shiny_app", "shiny_app"))

test_that("the dashboard builds and every output evaluates on the snapshot", {
  skip_if(is.null(app_dir), "shiny_app/ not available")
  for (p in c("shiny", "bslib", "dygraphs", "DT")) skip_if_not_installed(p)
  skip_if(!file.exists(file.path(app_dir, "..", "data", "snapshot", "MANIFEST.json")),
          "no data snapshot")

  withr::local_dir(app_dir)
  env <- new.env()
  app <- source("app.R", local = env)$value
  expect_s3_class(app, "shiny.appobj")

  shiny::testServer(env$server, {
    session$setInputs(ticker = "AAPL", source = "snapshot", model = "arma_garch", h = 5,
                      ma_type = "SMA", ma_period = 50, res_ticker = "POOLED", res_h = 1)
    expect_s3_class(prices_r(), "xts")
    expect_equal(attr(prices_r(), "source"), "snapshot")
    expect_match(output$vb_close, "^[0-9.]+$")
    # rendered htmlwidgets are serialised to JSON inside testServer
    expect_s3_class(output$price_plot, "json")
    expect_match(as.character(output$price_plot), "Adjusted close")

    fc <- forecast_r()
    expect_equal(nrow(fc$path), 5)
    expect_true(all(is.finite(fc$path$point)))
    expect_true(all(fc$path$sd > 0))
    tbl <- output$fc_table
    expect_true(grepl("arma_garch", tbl))
    expect_true(grepl("random walk", tbl))
    expect_match(as.character(output$fc_plot), "forecast origin")

    expect_match(as.character(output$vol_plot), "GARCH")
    expect_true(grepl("garch11", output$vol_table))

    # an ML model without a forecast path only reports the terminal horizon
    session$setInputs(model = "elastic_net", h = 3)
    expect_equal(forecast_r()$path$k, 3)
  })
})

test_that("an unknown ticker on the snapshot source fails with a readable message", {
  skip_if(is.null(app_dir), "shiny_app/ not available")
  for (p in c("shiny", "bslib", "dygraphs", "DT")) skip_if_not_installed(p)
  withr::local_dir(app_dir)
  env <- new.env()
  source("app.R", local = env)
  shiny::testServer(env$server, {
    session$setInputs(ticker = "NOPE", source = "snapshot", model = "naive_zero", h = 1,
                      ma_type = "SMA", ma_period = 50)
    expect_error(prices_r(), "No snapshot for NOPE")
  })
})
