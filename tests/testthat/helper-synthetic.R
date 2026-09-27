# Deterministic synthetic OHLCV series with GARCH-like volatility clustering,
# so that tests never touch the network.
synthetic_prices <- function(n = 1500, seed = 1, start = as.Date("2015-01-01")) {
  set.seed(seed)
  sigma2 <- numeric(n)
  eps <- numeric(n)
  sigma2[1] <- 1e-4
  for (t in 2:n) {
    sigma2[t] <- 2e-6 + 0.08 * eps[t - 1]^2 + 0.9 * sigma2[t - 1]
    eps[t] <- sqrt(sigma2[t]) * rnorm(1)
  }
  ret <- 0.0003 + eps
  close <- 100 * exp(cumsum(ret))
  open <- close * exp(rnorm(n, 0, 0.004))
  high <- pmax(open, close) * exp(abs(rnorm(n, 0, 0.006)))
  low <- pmin(open, close) * exp(-abs(rnorm(n, 0, 0.006)))
  volume <- round(1e6 * exp(rnorm(n, 0, 0.3)))
  dates <- start + seq_len(n) - 1
  xts::xts(
    data.frame(Open = open, High = high, Low = low, Close = close,
               Volume = volume, Adjusted = close),
    order.by = dates
  )
}
