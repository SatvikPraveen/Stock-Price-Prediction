# Regression test: background workers attach only stockcast. Unless the
# package itself pulls in the xts and zoo namespaces, subsetting an xts
# object there silently falls through to matrix indexing and the date index
# is lost (dates become row numbers).
test_that("make_features keeps Date columns in a fresh R process", {
  skip_if_not_installed("callr")
  skip_if(!any(dir.exists(file.path(.libPaths(), "stockcast"))),
          "stockcast is not installed; run `make install`")
  x <- synthetic_prices(200)
  cls <- callr::r(function(x) {
    library(stockcast)
    feat <- make_features(x)
    c(class(feat$date), class(zoo::index(clean_prices(x))))
  }, args = list(x = x))
  expect_equal(cls, c("Date", "Date"))
})

test_that("the NAMESPACE imports xts and zoo so their S3 methods are registered", {
  ns <- readLines(system.file("NAMESPACE", package = "stockcast"))
  expect_true(any(grepl("^importFrom\\(xts", ns)))
  expect_true(any(grepl("^importFrom\\(zoo", ns)))
})
