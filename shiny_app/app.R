# stockcast dashboard
#
# Multi-ticker price explorer, genuine h-day-ahead return/price forecasts
# with prediction intervals from any registered model, a volatility view,
# and the walk-forward leaderboards produced by scripts/run_experiment.R.
#
# The app works in two layouts:
#   * inside the repository (shiny::runApp("shiny_app")): package code is
#     sourced from ../R, data from ../data/snapshot, results from
#     ../results/latest;
#   * as a self-contained deployment bundle (see .github/workflows/deploy.yml):
#     R/, data/snapshot and results/latest are copied into the app folder.
#     Shiny auto-sources every file in R/.

library(shiny)
library(bslib)
library(dygraphs)
library(DT)
library(xts)
library(zoo)

if (!dir.exists("R")) {
  for (f in sort(list.files("../R", pattern = "\\.R$", full.names = TRUE))) source(f)
}
data_dir <- if (dir.exists("data/snapshot")) "data/snapshot" else "../data/snapshot"
results_dir <- if (dir.exists("results/latest")) "results/latest" else "../results/latest"
if (dir.exists(file.path(results_dir, "figures"))) {
  addResourcePath("figures", file.path(results_dir, "figures"))
}

manifest <- read_manifest(data_dir)
snapshot_tickers <- names(manifest)
if (length(snapshot_tickers) == 0) snapshot_tickers <- "AAPL"
registry <- model_registry()
return_models <- names(Filter(function(m) m$task == "return", registry))
vol_models <- names(Filter(function(m) m$task == "volatility", registry))
z95 <- qnorm(0.975)

read_result <- function(name) {
  p <- file.path(results_dir, name)
  if (file.exists(p)) read.csv(p, stringsAsFactors = FALSE) else NULL
}
leaderboard_return <- read_result("leaderboard_return.csv")
leaderboard_vol <- read_result("leaderboard_volatility.csv")
strategy_tbl <- read_result("strategy.csv")
run_summary <- if (file.exists(file.path(results_dir, "summary.json"))) {
  jsonlite::read_json(file.path(results_dir, "summary.json"))
}

# ---- UI --------------------------------------------------------------------

ui <- page_sidebar(
  title = "stockcast: out-of-sample equity forecasting",
  theme = bs_theme(version = 5, bootswatch = "flatly"),
  sidebar = sidebar(
    width = 320,
    selectizeInput("ticker", "Ticker", choices = snapshot_tickers, selected = snapshot_tickers[1],
                   options = list(create = TRUE, placeholder = "Type any Yahoo ticker")),
    radioButtons("source", "Data source",
                 choices = c("Pinned snapshot (reproducible)" = "snapshot",
                             "Live Yahoo Finance" = "live"),
                 selected = "snapshot"),
    hr(),
    selectInput("model", "Return model", choices = return_models, selected = "arma_garch"),
    sliderInput("h", "Horizon (trading days)", min = 1, max = 21, value = 5, step = 1),
    hr(),
    selectInput("ma_type", "Moving average", choices = c("SMA", "EMA")),
    numericInput("ma_period", "MA period", value = 50, min = 5, max = 250),
    hr(),
    helpText("Forecasts are made from the last observation in the data. ",
             "See the Methodology tab before reading anything into a point forecast.")
  ),
  navset_card_tab(
    id = "tabs",
    nav_panel(
      "Prices",
      layout_columns(
        fill = FALSE,
        value_box("Last close", textOutput("vb_close"), showcase = icon("dollar-sign")),
        value_box("Annualised vol (21d)", textOutput("vb_vol"), showcase = icon("wave-square")),
        value_box("Observations", textOutput("vb_n"), showcase = icon("database"))
      ),
      dygraphOutput("price_plot", height = "420px"),
      helpText(textOutput("data_note"))
    ),
    nav_panel(
      "Forecast",
      layout_columns(
        col_widths = c(8, 4),
        card(card_header(textOutput("fc_title")), dygraphOutput("fc_plot", height = "400px")),
        card(card_header("Forecast summary"), tableOutput("fc_table"),
             helpText(textOutput("fc_desc")))
      ),
      card(
        card_header("How to read this"),
        p("The model is estimated on the full history of the selected ticker and produces the ",
          "distribution of the cumulative log return over the next h trading days. The band is a ",
          "95% Gaussian interval; prices are obtained by exponentiating. The random-walk row is the ",
          "benchmark every model is tested against in the walk-forward study, and on daily data the ",
          "point forecasts of all models are typically indistinguishable from it.")
      )
    ),
    nav_panel(
      "Volatility",
      dygraphOutput("vol_plot", height = "380px"),
      card(card_header("h-day variance forecasts from the last observation"),
           tableOutput("vol_table"))
    ),
    nav_panel(
      "Walk-forward results",
      uiOutput("results_ui")
    ),
    nav_panel(
      "Methodology",
      card(
        h4("What this app does and does not claim"),
        p("This project evaluates whether standard forecasting models can predict daily equity ",
          "returns and their variance out of sample. Every number on the Walk-forward results tab ",
          "comes from a rolling-origin evaluation: models see data only up to each forecast origin, ",
          "are refit monthly, and are scored on the realised outcome. Models are compared to a ",
          "random walk with the Diebold-Mariano test (Harvey-Leybourne-Newbold correction) and the ",
          "Pesaran-Timmermann test of directional accuracy."),
        p("Forecasting daily returns is close to impossible; forecasting volatility is not. The ",
          "results tab shows both. Nothing here is investment advice."),
        p(a("Full methodology, references and reproduction instructions on GitHub",
            href = "https://github.com/SatvikPraveen/Stock-Price-Prediction", target = "_blank"))
      )
    )
  )
)

# ---- server ----------------------------------------------------------------

server <- function(input, output, session) {

  prices_r <- reactive({
    req(input$ticker)
    tk <- toupper(trimws(input$ticker))
    if (input$source == "live") {
      live <- tryCatch(download_prices(tk, from = "2010-01-01"), error = function(e) NULL)
      if (!is.null(live) && nrow(live) > 300) return(structure(live, source = "live"))
      showNotification("Live download failed; using the pinned snapshot.", type = "warning")
    }
    if (file.exists(file.path(data_dir, paste0(tk, ".csv")))) {
      return(structure(read_snapshot(tk, data_dir), source = "snapshot"))
    }
    validate(need(FALSE, paste0("No snapshot for ", tk, ". Switch to live data to download it.")))
  })

  feat_r <- reactive(make_features(prices_r()))

  output$data_note <- renderText({
    p <- prices_r()
    sprintf("Source: %s. %d trading days from %s to %s.", attr(p, "source"), nrow(p),
            format(start(p)), format(end(p)))
  })
  output$vb_close <- renderText(sprintf("%.2f", tail(as.numeric(prices_r()$Close), 1)))
  output$vb_vol <- renderText({
    f <- feat_r()
    sprintf("%.1f%%", 100 * tail(f$vol_21, 1) * sqrt(252))
  })
  output$vb_n <- renderText(format(nrow(prices_r()), big.mark = ","))

  output$price_plot <- renderDygraph({
    p <- prices_r()
    adj <- p$Adjusted
    n <- max(5, min(input$ma_period, nrow(p) - 1))
    ma <- if (input$ma_type == "SMA") TTR::SMA(adj, n) else TTR::EMA(adj, n)
    bb <- TTR::BBands(adj, n = 20, sd = 2)
    series <- merge(Adjusted = adj, MA = ma, Lower = bb[, "dn"], Upper = bb[, "up"])
    colnames(series) <- c("Adjusted close", paste0(input$ma_type, "(", n, ")"), "BB lower", "BB upper")
    dygraph(series, main = paste(input$ticker, "adjusted close")) %>%
      dySeries(c("BB lower", "Adjusted close", "BB upper"), label = "Adjusted close") %>%
      dyOptions(fillAlpha = 0.15) %>%
      dyRangeSelector(height = 30) %>%
      dyLegend(show = "follow")
  })

  forecast_r <- reactive({
    f <- feat_r()
    h <- input$h
    model <- registry[[input$model]]
    withProgress(message = paste("Fitting", input$model), value = 0.5, {
      fit <- model$fit(f, h)
      ks <- if (isTRUE(model$path)) seq_len(h) else h
      path <- lapply(ks, function(k) {
        p <- model$predict(fit, f, k)
        data.frame(k = k, point = p$point, sd = p$sd)
      })
    })
    path <- do.call(rbind, path)
    bench <- registry$naive_zero$predict(NULL, f, h)
    list(path = path, bench = bench, last_close = tail(f$close, 1), last_date = tail(f$date, 1))
  })

  output$fc_title <- renderText(sprintf("%s: %d-day-ahead forecast from %s (%s)",
                                        input$ticker, input$h, format(forecast_r()$last_date),
                                        input$model))

  output$fc_plot <- renderDygraph({
    fc <- forecast_r()
    f <- feat_r()
    hist <- tail(f, 120)
    hist_x <- xts(cbind(Actual = hist$close, Mean = NA, Lower = NA, Upper = NA), order.by = hist$date)
    # forecast dates: next business days (approximation for plotting only)
    fdates <- seq(fc$last_date + 1, by = "day", length.out = 2 * input$h + 6)
    fdates <- fdates[!weekdays(fdates) %in% c("Saturday", "Sunday")][seq_len(input$h)]
    path <- fc$path
    fx <- xts(cbind(Actual = NA,
                    Mean = fc$last_close * exp(path$point),
                    Lower = fc$last_close * exp(path$point - z95 * path$sd),
                    Upper = fc$last_close * exp(path$point + z95 * path$sd)),
              order.by = fdates[path$k])
    dygraph(rbind(hist_x, fx), main = "Price path with 95% interval") %>%
      dySeries("Actual", label = "Close") %>%
      dySeries(c("Lower", "Mean", "Upper"), label = "Forecast") %>%
      dyOptions(fillAlpha = 0.25, drawPoints = TRUE, pointSize = 2) %>%
      dyEvent(fc$last_date, "forecast origin", labelLoc = "bottom")
  })

  output$fc_table <- renderTable({
    fc <- forecast_r()
    last <- fc$path[nrow(fc$path), ]
    rows <- rbind(
      data.frame(Model = input$model, point = last$point, sd = last$sd),
      data.frame(Model = "naive_zero (random walk)", point = fc$bench$point, sd = fc$bench$sd)
    )
    data.frame(
      Model = rows$Model,
      `Expected return` = sprintf("%+.2f%%", 100 * rows$point),
      `Price forecast` = sprintf("%.2f", fc$last_close * exp(rows$point)),
      `95% interval` = sprintf("%.2f to %.2f",
                               fc$last_close * exp(rows$point - z95 * rows$sd),
                               fc$last_close * exp(rows$point + z95 * rows$sd)),
      check.names = FALSE
    )
  })
  output$fc_desc <- renderText(registry[[input$model]]$description)

  garch_r <- reactive({
    f <- feat_r()
    r <- f$ret[!is.na(f$ret)]
    fit <- suppressWarnings(rugarch::ugarchfit(garch_spec(), r, solver = "hybrid"))
    list(fit = fit, dates = f$date[!is.na(f$ret)])
  })

  output$vol_plot <- renderDygraph({
    g <- garch_r()
    f <- feat_r()
    cond <- xts(as.numeric(rugarch::sigma(g$fit)) * sqrt(252), order.by = g$dates)
    realised <- xts(sqrt(pmax(f$rv_21, 0) * 252), order.by = f$date)
    series <- merge(cond, realised)
    colnames(series) <- c("GARCH(1,1) conditional vol", "Realised vol (21d Garman-Klass)")
    dygraph(series, main = paste(input$ticker, "annualised volatility")) %>%
      dyAxis("y", label = "annualised sd") %>%
      dyRangeSelector(height = 30) %>%
      dyLegend(show = "follow")
  })

  output$vol_table <- renderTable({
    f <- feat_r()
    h <- input$h
    rows <- lapply(vol_models, function(nm) {
      m <- registry[[nm]]
      v <- tryCatch(m$predict(m$fit(f, h), f, h)$var, error = function(e) NA_real_)
      data.frame(Model = nm, Description = m$description,
                 `h-day variance` = formatC(v, digits = 3, format = "e"),
                 `Annualised vol` = sprintf("%.1f%%", 100 * sqrt(v / h * 252)),
                 check.names = FALSE)
    })
    do.call(rbind, rows)
  })

  output$results_ui <- renderUI({
    if (is.null(leaderboard_return)) {
      return(card(p("No experiment results found. Run `make experiment` to populate results/latest/.")))
    }
    tickers <- c("POOLED", setdiff(unique(leaderboard_return$ticker), "POOLED"))
    tagList(
      if (!is.null(run_summary)) {
        p(sprintf("Run %s (commit %s): %s tickers, out-of-sample %s to %s, %s forecasts.",
                  run_summary$run_id, run_summary$git_sha, run_summary$n_tickers,
                  run_summary$oos_start, run_summary$oos_end,
                  format(run_summary$n_forecasts, big.mark = ",")))
      },
      layout_columns(
        col_widths = c(3, 3),
        selectInput("res_ticker", "Ticker", choices = tickers, selected = "POOLED"),
        selectInput("res_h", "Horizon", choices = sort(unique(leaderboard_return$h)))
      ),
      navset_card_underline(
        nav_panel("Return forecasts", DTOutput("res_return")),
        nav_panel("Volatility forecasts", DTOutput("res_vol")),
        nav_panel("Trading backtest", DTOutput("res_strategy")),
        nav_panel("Figures",
                  tags$img(src = "figures/cumulative_sse_h1.png", style = "width:100%"),
                  tags$img(src = "figures/leaderboard_rmse.png", style = "width:100%"),
                  tags$img(src = "figures/leaderboard_qlike.png", style = "width:100%"),
                  tags$img(src = "figures/equity_curves.png", style = "width:100%"))
      )
    )
  })

  output$res_return <- renderDT({
    req(input$res_ticker, input$res_h)
    d <- leaderboard_return[leaderboard_return$ticker == input$res_ticker &
                              leaderboard_return$h == as.integer(input$res_h), ]
    d <- d[order(d$rmse), c("model", "n", "rmse", "oos_r2", "dir_acc", "pt_p", "dm_p",
                            "crps", "coverage_95")]
    datatable(d, rownames = FALSE, options = list(pageLength = 10, dom = "t")) %>%
      formatSignif(c("rmse", "oos_r2", "crps"), 4) %>%
      formatRound(c("dir_acc", "coverage_95"), 3) %>%
      formatSignif(c("pt_p", "dm_p"), 3)
  })

  output$res_vol <- renderDT({
    req(input$res_ticker, input$res_h, leaderboard_vol)
    d <- leaderboard_vol[leaderboard_vol$ticker == input$res_ticker &
                           leaderboard_vol$h == as.integer(input$res_h), ]
    d <- d[order(d$qlike_r2), c("model", "n", "qlike_r2", "dm_qlike_p_r2", "qlike_gk",
                                "dm_qlike_p_gk", "mse_r2")]
    datatable(d, rownames = FALSE, options = list(pageLength = 10, dom = "t")) %>%
      formatSignif(c("qlike_r2", "qlike_gk", "mse_r2", "dm_qlike_p_r2", "dm_qlike_p_gk"), 4)
  })

  output$res_strategy <- renderDT({
    req(input$res_ticker, strategy_tbl)
    d <- strategy_tbl[strategy_tbl$ticker == input$res_ticker, ]
    d <- d[order(d$rule, -d$sharpe), c("rule", "model", "ann_return", "ann_vol", "sharpe",
                                       "sharpe_se", "max_drawdown", "total_return")]
    datatable(d, rownames = FALSE, options = list(pageLength = 20, dom = "t")) %>%
      formatRound(c("ann_return", "ann_vol", "sharpe", "sharpe_se", "max_drawdown", "total_return"), 3)
  })
}

shinyApp(ui = ui, server = server)
