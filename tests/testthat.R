library(testthat)

test_check_dir <- function() {
  testthat::test_dir("testthat", reporter = "summary")
}

test_check_dir()
