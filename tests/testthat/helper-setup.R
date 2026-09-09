# Locates and sources shiny_app/app.R so its top-level functions
# (fetch_stock_data, train_model) are available to the tests, regardless
# of whether tests are run from the repo root or from this directory.
# Sourcing app.R is safe: the trailing shinyApp() call builds an app
# object but does not launch it when the file is source()'d.
app_path <- Find(file.exists, c(
  "shiny_app/app.R",
  file.path("..", "..", "shiny_app", "app.R"),
  file.path("..", "shiny_app", "app.R")
))

if (is.null(app_path)) {
  stop("Could not locate shiny_app/app.R relative to the test working directory")
}

suppressPackageStartupMessages(source(normalizePath(app_path)))
