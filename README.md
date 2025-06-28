# 📌 **Stock Price Prediction with RShiny**

![License](https://img.shields.io/github/license/SatvikPraveen/stock-price-prediction)
![Repo Size](https://img.shields.io/github/repo-size/SatvikPraveen/stock-price-prediction)
![Issues](https://img.shields.io/github/issues/SatvikPraveen/stock-price-prediction)
![Stars](https://img.shields.io/github/stars/SatvikPraveen/stock-price-prediction?style=social)
![R](https://img.shields.io/badge/R-Compatible-blue?logo=r)
![Shiny](https://img.shields.io/badge/Built%20with-RShiny-75AADB?logo=rstudio)

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
git clone https://github.com/SatvikPraveen/stock-price-prediction.git
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

1. **Fetches Real-Time Data**
   - Uses `quantmod` to get the latest AAPL stock prices from Yahoo Finance.
2. **Visualizes Historical Trends**

   - Dynamic `dygraphs` plots for stock prices and **customizable moving averages (SMA/EMA)**.

3. **Predicts Closing Price**

   - A **Linear Regression Model** predicts the **Closing Price** based on user inputs:
     - Open Price
     - High Price
     - Low Price

4. **Interactive UI with Tabbed Layout**

   - **Stock Chart Tab:** Displays historical price trends.
   - **Moving Average Tab:** Enables SMA/EMA analysis.
   - **Prediction Tab:** Displays model predictions.

5. **Deployed on ShinyApps.io**
   - Accessible **from any device** with an internet connection.

---

## 🌍 Live App Deployment

Our interactive RShiny app is **live and accessible** at:

🔗 [Stock Market Closing Price Predictor for Apple](https://my-app-01.shinyapps.io/shiny_app/)

### **📸 Application Interface**

<img width="1096" alt="image" src="https://github.com/user-attachments/assets/37e1b59c-a6f5-411f-8221-fbd978a23661" />


### **📌 How to Use the App**

1. **Explore Stock Trends** – View historical data for AAPL stock.
2. **Select Moving Averages** – Choose between **SMA** and **EMA** for trend analysis.
3. **Predict Closing Price** – Input Open, High, and Low prices to get a predicted **Closing Price**.

### **🛠 Troubleshooting Deployment Issues**

- If the app **does not load**, try refreshing the page.
- If the app is **slow**, it may be due to free-tier ShinyApps.io limitations.
- If you encounter **errors**, clone the repository and run locally using:

  ```r
  shiny::runApp("shiny_app")
  ```

---

## 📌 **Future Improvements**

✅ Improved UI with tabbed layout and moving averages.  
✅ Implemented ARIMA & STLF models for forecasting.

🚀 **Upcoming Enhancements:**

- **Add More Financial Indicators** – Implement RSI and Bollinger Bands.
- **Optimize Performance** – Improve app response time for large datasets.
- **Expand Predictive Modeling** – Integrate deep learning-based models for stock predictions.

---

## 💡 **Contributions**

Feel free to open issues, suggest improvements, or contribute by making a pull request.

### stock-price-prediction

Stock price prediction using historical data from Yahoo Finance, built with R and an interactive RShiny dashboard.
