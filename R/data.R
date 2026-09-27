#' Standardise Yahoo Finance column names
#'
#' `quantmod::getSymbols()` returns columns such as `AAPL.Open`. This strips
#' the ticker prefix and keeps the canonical OHLCV(A) columns.
#'
#' @param x An `xts` object as returned by `quantmod::getSymbols()`.
#' @return An `xts` object with columns Open, High, Low, Close, Volume, Adjusted.
#' @keywords internal
standardise_ohlcv <- function(x) {
  colnames(x) <- sub("^.*\\.", "", colnames(x))
  need <- c("Open", "High", "Low", "Close", "Volume", "Adjusted")
  missing <- setdiff(need, colnames(x))
  if (length(missing) > 0) {
    stop("Price data is missing columns: ", paste(missing, collapse = ", "))
  }
  x[, need]
}

#' Clean a daily price series
#'
#' Removes rows with missing or non-positive prices, drops duplicated dates
#' and sorts by date. Non-positive prices break log returns and are almost
#' always data errors.
#'
#' @param x An `xts` object with OHLCV(A) columns.
#' @return A cleaned `xts` object.
#' @export
clean_prices <- function(x) {
  x <- standardise_ohlcv(x)
  keep <- stats::complete.cases(zoo::coredata(x))
  price_cols <- c("Open", "High", "Low", "Close", "Adjusted")
  keep <- keep & apply(zoo::coredata(x[, price_cols]) > 0, 1, all)
  x <- x[keep, ]
  x <- x[!duplicated(zoo::index(x)), ]
  x[order(zoo::index(x)), ]
}

#' Download daily OHLCV data from Yahoo Finance
#'
#' @param ticker Ticker symbol, e.g. `"AAPL"`.
#' @param from Start date (character or Date).
#' @param to End date (character or Date). Defaults to today.
#' @return A cleaned `xts` object with columns Open, High, Low, Close, Volume,
#'   Adjusted.
#' @export
download_prices <- function(ticker, from = "2010-01-01", to = Sys.Date()) {
  x <- quantmod::getSymbols(
    ticker, src = "yahoo", from = as.Date(from), to = as.Date(to),
    auto.assign = FALSE
  )
  clean_prices(x)
}

snapshot_path <- function(cache_dir, ticker) {
  file.path(cache_dir, paste0(ticker, ".csv"))
}

manifest_path <- function(cache_dir) file.path(cache_dir, "MANIFEST.json")

#' Write a price series to the on-disk snapshot and update the manifest
#'
#' The manifest records a SHA-256 hash of every CSV, its date range and the
#' download time, so that a run can be tied to the exact data it used.
#'
#' @param x An `xts` price object.
#' @param ticker Ticker symbol.
#' @param cache_dir Snapshot directory.
#' @return The manifest entry (invisibly).
#' @export
write_snapshot <- function(x, ticker, cache_dir = "data/snapshot") {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  path <- snapshot_path(cache_dir, ticker)
  df <- data.frame(Date = format(zoo::index(x)), zoo::coredata(x),
                   check.names = FALSE)
  write.csv(df, path, row.names = FALSE)

  entry <- list(
    ticker = ticker,
    file = basename(path),
    sha256 = digest::digest(file = path, algo = "sha256"),
    rows = nrow(x),
    first_date = format(min(zoo::index(x))),
    last_date = format(max(zoo::index(x))),
    downloaded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    source = "Yahoo Finance via quantmod::getSymbols"
  )
  manifest <- read_manifest(cache_dir)
  manifest[[ticker]] <- entry
  jsonlite::write_json(manifest, manifest_path(cache_dir),
                       auto_unbox = TRUE, pretty = TRUE)
  invisible(entry)
}

#' Read the snapshot manifest
#'
#' @param cache_dir Snapshot directory.
#' @return A named list of manifest entries (empty list if none).
#' @export
read_manifest <- function(cache_dir = "data/snapshot") {
  p <- manifest_path(cache_dir)
  if (!file.exists(p)) return(list())
  jsonlite::read_json(p)
}

#' Read a price series from the on-disk snapshot
#'
#' @param ticker Ticker symbol.
#' @param cache_dir Snapshot directory.
#' @param verify If `TRUE`, verify the file's SHA-256 against the manifest.
#' @return A cleaned `xts` object.
#' @export
read_snapshot <- function(ticker, cache_dir = "data/snapshot", verify = TRUE) {
  path <- snapshot_path(cache_dir, ticker)
  if (!file.exists(path)) {
    stop("No snapshot for ", ticker, " in ", cache_dir)
  }
  if (verify) {
    m <- read_manifest(cache_dir)[[ticker]]
    if (!is.null(m)) {
      h <- digest::digest(file = path, algo = "sha256")
      if (!identical(h, m$sha256)) {
        stop("Snapshot for ", ticker, " does not match manifest hash; ",
             "re-run snapshot_universe(refresh = TRUE) or restore the file.")
      }
    }
  }
  df <- read.csv(path, check.names = FALSE)
  x <- xts::xts(df[, setdiff(names(df), "Date")], order.by = as.Date(df$Date))
  clean_prices(x)
}

#' Get daily prices for one or more tickers, using the snapshot cache
#'
#' @param tickers Character vector of tickers.
#' @param from,to Date range used when downloading.
#' @param cache_dir Snapshot directory.
#' @param refresh If `TRUE`, always re-download and overwrite the snapshot.
#' @param verify Verify snapshot hashes against the manifest.
#' @return A named list of `xts` objects, one per ticker.
#' @export
get_prices <- function(tickers, from = "2010-01-01", to = Sys.Date(),
                       cache_dir = "data/snapshot", refresh = FALSE,
                       verify = TRUE) {
  out <- lapply(tickers, function(tk) {
    if (!refresh && file.exists(snapshot_path(cache_dir, tk))) {
      return(read_snapshot(tk, cache_dir, verify = verify))
    }
    x <- download_prices(tk, from = from, to = to)
    write_snapshot(x, tk, cache_dir)
    x
  })
  setNames(out, tickers)
}

#' Download and pin a whole universe of tickers
#'
#' @inheritParams get_prices
#' @return The manifest (invisibly).
#' @export
snapshot_universe <- function(tickers, from = "2010-01-01", to = Sys.Date(),
                              cache_dir = "data/snapshot", refresh = TRUE) {
  get_prices(tickers, from = from, to = to, cache_dir = cache_dir,
             refresh = refresh, verify = FALSE)
  invisible(read_manifest(cache_dir))
}
