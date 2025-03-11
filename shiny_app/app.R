# App.R
library(shiny)
library(quantmod)
library(dygraphs)
library(TTR)  # For moving averages

# Define UI for the app
ui <- fluidPage(
  tags$style(".dygraph-legend { left: 100px !important; }"),  # Adjust legend position
  titlePanel("Stock Market Closing Price Predictor For Apple"),
  sidebarLayout(
    sidebarPanel(
      numericInput("open_price", "Enter Open Price:", value = 100),
      numericInput("high_price", "Enter High Price:", value = 110),
      numericInput("low_price", "Enter Low Price:", value = 90),
      selectInput("ma_type", "Select Moving Average Type:", choices = c("SMA", "EMA")),
      numericInput("ma_period", "Enter Moving Average Period:", value = 20, min = 5),
      actionButton("predict", "Predict Closing Price"),
      width = 4
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("Stock Chart", dygraphOutput("stock_plot")),  
        tabPanel("Moving Average Chart", dygraphOutput("ma_plot")),
        tabPanel("Prediction", 
          br(),
          "Predicted Closing Price:",
          h4(textOutput("predicted_closing_price"))
        )
      ),
      width = 8
    )
  )
)

# Define server logic
server <- function(input, output) {
  
  # Function to fetch stock data
  fetch_stock_data <- function() {
    tryCatch({
      data <- quantmod::getSymbols("AAPL", src = "yahoo", auto.assign = FALSE)
      return(data)
    }, error = function(e) {
      return(NULL)
    })
  }
  
  # Function to train model
  train_model <- function(stock_data) {
    if (is.null(stock_data) || nrow(stock_data) == 0) {
      return(NULL)
    }
    model_data <- stock_data[, c("AAPL.Open", "AAPL.High", "AAPL.Low", "AAPL.Close")]
    colnames(model_data) <- c("OpenPrice", "HighPrice", "LowPrice", "ClosingPrice")
    model <- lm(ClosingPrice ~ OpenPrice + HighPrice + LowPrice, data = model_data)
    return(model)
  }
  
  # Generate stock plot
  output$stock_plot <- renderDygraph({  
    stock_data <- fetch_stock_data()
    if (!is.null(stock_data)) {
      dygraph(stock_data, main = "Stock Data") %>%
        dyAxis("y", label = "Price", valueRange = c(0, max(stock_data$AAPL.Close) * 1.1)) %>%
        dySeries("AAPL.Close", label = "Close") %>%
        dySeries("AAPL.High", label = "High") %>%
        dySeries("AAPL.Low", label = "Low") %>%
        dySeries("AAPL.Open", label = "Open")
    } else {
      dygraph(1, main = "No Data Available") %>%
        dyAxis("x", label = "Date") %>%
        dyAxis("y", label = "Price")
    }
  })
  
  # Generate moving average plot
  output$ma_plot <- renderDygraph({  
    stock_data <- fetch_stock_data()
    if (!is.null(stock_data)) {
      ma_period <- input$ma_period
      ma_type <- input$ma_type
      
      # Ensure AAPL.Close exists in the stock data
      if (!"AAPL.Close" %in% colnames(stock_data)) {
        return(NULL)
      }
      
      close_prices <- stock_data$AAPL.Close
      
      # Compute moving average
      if (ma_type == "SMA") {
        ma_values <- SMA(close_prices, n = ma_period)
      } else {
        ma_values <- EMA(close_prices, n = ma_period)
      }
      
      # Ensure matching time index
      ma_series <- xts(ma_values, order.by = index(stock_data))
      
      # Proper column naming
      combined_series <- cbind(Close = close_prices, MA = ma_series)
      colnames(combined_series) <- c("Close Price", paste0(ma_type, " (", ma_period, ")"))
      
      dygraph(combined_series, main = "Moving Average Chart") %>%
        dySeries("Close Price", label = "Close Price") %>%
        dySeries(paste0(ma_type, " (", ma_period, ")"), label = paste0(ma_type, " (", ma_period, ")"))
    } else {
      dygraph(1, main = "No Data Available") %>%
        dyAxis("x", label = "Date") %>%
        dyAxis("y", label = "Price")
    }
  })
  
  # Generate predicted closing price
  output$predicted_closing_price <- renderText({
    input$predict
    stock_data <- fetch_stock_data()
    model <- train_model(stock_data)
    if (!is.null(model)) {
      new_data <- data.frame(
        OpenPrice = input$open_price,
        HighPrice = input$high_price,
        LowPrice = input$low_price
      )
      predicted_price <- predict(model, newdata = new_data)
      round(predicted_price, 2)
    } else {
      "N/A"
    }
  })
}

# Run the application
shinyApp(ui = ui, server = server)
