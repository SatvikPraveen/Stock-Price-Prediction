test_that("clean_prices drops NA, non-positive and duplicated rows and sorts", {
  x <- synthetic_prices(50)
  colnames(x) <- paste0("ZZZ.", colnames(x))
  bad <- x[c(1, 2, 3, 3, 10), ]
  zoo::coredata(bad)[2, "ZZZ.Close"] <- NA
  zoo::coredata(bad)[5, "ZZZ.Low"] <- -1
  out <- clean_prices(bad[c(5, 1, 2, 3, 4), ])
  expect_equal(colnames(out), c("Open", "High", "Low", "Close", "Volume", "Adjusted"))
  expect_equal(nrow(out), 2)
  expect_true(!is.unsorted(zoo::index(out)))
})

test_that("snapshot round-trips through disk and the manifest hash is verified", {
  dir <- withr::local_tempdir()
  x <- synthetic_prices(120)
  write_snapshot(x, "SYN", dir)
  m <- read_manifest(dir)
  expect_named(m, "SYN")
  expect_equal(m$SYN$rows, 120)
  y <- read_snapshot("SYN", dir)
  expect_equal(nrow(y), 120)
  expect_equal(as.numeric(y$Close), as.numeric(x$Close), tolerance = 1e-10)

  # tamper with the file -> hash mismatch is detected
  writeLines(c(readLines(file.path(dir, "SYN.csv")), "2030-01-01,1,1,1,1,1,1"),
             file.path(dir, "SYN.csv"))
  expect_error(read_snapshot("SYN", dir), "does not match manifest hash")
  expect_s3_class(read_snapshot("SYN", dir, verify = FALSE), "xts")
})

test_that("get_prices uses the cache without touching the network", {
  dir <- withr::local_tempdir()
  write_snapshot(synthetic_prices(100), "SYN", dir)
  out <- get_prices("SYN", cache_dir = dir)
  expect_named(out, "SYN")
  expect_equal(nrow(out$SYN), 100)
})
