# 📌 **Stock Price Prediction with RShiny**

📈 _Predicting AAPL stock prices using historical data from Yahoo Finance, implemented in R with an interactive RShiny dashboard._

---

## 🚀 **Project Overview**

This project analyzes Apple Inc. (**AAPL**) stock data using **quantitative methods** and **statistical modeling**. It features an **interactive dashboard built with RShiny** to visualize trends and make predictions.

---

## 📚 **Project Structure**

```bash
📚 stock-price-prediction
 ├── 📜 README.md            <- Project documentation
 ├── 📂 data/                <- Stock data (raw & processed)
 ├── 📂 notebooks/           <- Jupyter/R Markdown notebooks for analysis
 ├── 📂 shiny_app/           <- RShiny dashboard with prediction model
 ├── 📂 results/             <- Forecast plots & evaluation metrics
 ├── 📝 requirements.txt     <- Python dependencies (if needed)
 ├── 📝 dependencies.R       <- R dependencies installation script
 ├── 📝 .gitignore           <- Ignore unnecessary files
```

---

## 🔧 **Setup Instructions**

### **1⃣ Clone the Repository**

```bash
git clone https://github.com/YOUR_USERNAME/stock-price-prediction.git
cd stock-price-prediction
```

### **2⃣ Install Dependencies**

#### **For R users:**

```r
# Install required R packages
install.packages(c("quantmod", "lubridate", "rvest", "ggplot2", "caret", "lmtest", "tseries", "shiny", "dygraphs", "TTR"))
```

#### **For Python users (if using Jupyter for analysis):**

```bash
pip install -r requirements.txt
```

---

## 📊 **Data Source**

- The stock price data is retrieved from **Yahoo Finance** using the `quantmod` package in R.
- The dataset contains:
  - **Date**
  - **Open, High, Low, Close Prices**
  - **Volume & Adjusted Close**

---

## 🛠 **Features**

✔ **Stock Data Extraction** from Yahoo Finance  
✔ **Exploratory Data Analysis** using ggplot2  
✔ **Time-Series Forecasting Models (ARIMA, STLF)**  
✔ **Moving Averages (SMA & EMA) for Trend Analysis**  
✔ **Interactive RShiny Dashboard with Prediction Feature**

---

## 🎮 **How to Run the RShiny App**

```r
# Navigate to the shiny_app directory
cd shiny_app

# Run the app
shiny::runApp()
```

This will launch a **web-based interactive dashboard**.

---

## 🎮 **How the RShiny App Works**

- Uses **Linear Regression** based on Open, High, and Low prices to predict Closing Price.
- Allows users to visualize **Stock Trends & Moving Averages (SMA, EMA)** dynamically.
- Fetches **real-time stock data** from Yahoo Finance.

## 📌 **Next Steps**

- ✅ Improved UI with tabbed layout and moving averages.
- ✅ Implemented ARIMA & STLF models for forecasting.
- 🚀 Consider adding more financial indicators (RSI, Bollinger Bands).
- 🚀 Deploy the app using ShinyApps.io.

---

## 💡 **Contributions**

Feel free to open issues, suggest improvements, or contribute by making a pull request.

### stock-price-prediction

Stock price prediction using historical data from Yahoo Finance, implemented in R with an interactive RShiny dashboard.
