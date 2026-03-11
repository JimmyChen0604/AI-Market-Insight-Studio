# Market Insight Studio

A real-time financial analysis and AI prediction dashboard built with R/Shiny, tracking 7 major tech stocks with live quotes, news aggregation, and quantitative model forecasting.

**Live App:** [market-insight-studio on DigitalOcean](https://your-app-url.ondigitalocean.app)

---

## Tracked Stocks

| Ticker | Company |
|--------|---------|
| AAPL | Apple |
| TSLA | Tesla |
| META | Meta |
| NVDA | NVIDIA |
| GOOGL | Alphabet |
| AMZN | Amazon |
| MSFT | Microsoft |

Benchmark index: **SPY** (S&P 500 ETF)

---

## Features

### Data Tab
- **Live stock quotes** with auto-refresh (Finnhub real-time API)
- Price cards showing current price, daily change, and volume
- **Analytics sub-page** with:
  - Model Parameters table (GBM, Binomial Lattice, Single Index Model)
  - Historical Prices table (OHLCV)
  - Downloadable CSV export

### News Tab
- Company news from Finnhub (filterable by stock, 7/30/90 day range)
- Timestamps in US Eastern Time
- Clickable article links

### Reporting Tab (AI Multi-Agent)
- **Geometric Brownian Motion (GBM)** forecast with confidence bands
- **Binomial Lattice (CRR)** price tree projection
- **Single Index Model (SIM)** regression against SPY
- **RAG + Parallel Multi-Agent pipeline** — 6 specialist analysts run in parallel via `httr2::req_perform_parallel`, each with role-specific RAG-retrieved CSV data, followed by a Portfolio Manager synthesis phase
- Automatic fallback to single-call approach if multi-agent pipeline fails
- Supports OpenAI GPT-4o-mini and Ollama backends

---

## Quantitative Models

| Model | Description |
|-------|-------------|
| GBM | Estimates annualized drift (mu) and volatility (sigma) from log returns; projects expected price path with 5-95% confidence interval |
| Binomial Lattice | CRR parameterization with risk-neutral and real-world up-probabilities; 22-step tree over 1-month horizon |
| Single Index Model | OLS regression of stock returns vs SPY; produces alpha, beta, R-squared, and confidence intervals |

Additional statistics: Shapiro-Wilk normality test, skewness, kurtosis, max drawdown, realized/downside/20-day volatility, outlier fraction.

---

## RAG Data Files

These CSV files are auto-exported on each data refresh for downstream RAG pipelines:

| File | Description |
|------|-------------|
| `historical_prices.csv` | Daily OHLCV prices for all 7 stocks + SPY |
| `model_parameters.csv` | Daily snapshots of computed model parameters (from 2026-02-01 onward) |
| `news_archive.csv` | Accumulated company news with timestamps |
| `rag_data_column_dictionary.csv` | Column definitions for the model parameters |

---

## Setup

### Prerequisites

- R >= 4.1 (required for native pipe `|>`)
- API keys for Finnhub, OpenAI, and optionally Ollama

### 1. Install R packages

```bash
Rscript install_packages.R
```

### 2. Configure API keys

Create a `.env` file in this directory:

```
FINNHUB_API_KEY=your_finnhub_key
OPENAI_API_KEY=your_openai_key
OLLAMA_API_KEY=your_ollama_key_or_leave_empty
```

- **Finnhub** (free, 60 req/min): [finnhub.io](https://finnhub.io/register) — real-time quotes, historical candles, company news
- **OpenAI** — GPT-4o-mini for AI predictions and reports
- **Ollama** (optional) — leave empty or set to `local` for local Ollama; or set cloud key

### 3. Run locally

```bash
R -e "shiny::runApp('.', port = 3838)"
```

Or use the restart script:

```bash
./restart_app.sh 3838 --open
```

---

## Docker Deployment

```bash
docker build -t market-insight .
docker run -p 8080:8080 \
  -e FINNHUB_API_KEY=your_key \
  -e OPENAI_API_KEY=your_key \
  -e OLLAMA_API_KEY=your_key \
  market-insight
```

The app is configured for DigitalOcean App Platform with environment variables set in the dashboard.

---

## Multi-Agent Architecture

The reporting pipeline uses a two-phase RAG + parallel multi-agent workflow:

```
Phase 1 (Parallel):  6 specialist agents run simultaneously
┌──────────────────┬──────────────────┬──────────────────┐
│ Fundamentals     │ News Analyst     │ Technical/Quant  │
│ key_financials   │ news_archive     │ model_parameters │
│ company_fin      │                  │ historical_prices│
│ valuation        │                  │ column_dict      │
├──────────────────┼──────────────────┼──────────────────┤
│ Bull Researcher  │ Bear Researcher  │ Risk Manager     │
│ key_financials   │ key_financials   │ model_parameters │
│ company_fin      │ company_fin      │ credit_metrics   │
│ recent_news      │ risk_indicators  │                  │
└──────────────────┴──────────────────┴──────────────────┘
                          │
                          ▼
Phase 2 (Sequential):  Portfolio Manager synthesizes all outputs
                          │
                          ▼
                   Final JSON Report
         (same schema as single-call approach)
```

Each agent retrieves only the CSV data relevant to its role (RAG retrieval), receives a focused system prompt, and returns structured JSON. The Portfolio Manager aggregates all 6 outputs into the final report.

If the multi-agent pipeline fails, the system falls back to the original single monolithic LLM call.

## Project Structure

```
.
├── app.R                           # Main Shiny entry point
├── global.R                        # Constants, libraries, API keys, source loading
├── api.R                           # API functions (Finnhub, Yahoo, OpenAI, Ollama)
├── models.R                        # Financial models (GBM, Lattice, SIM), caching, export
├── agents.R                        # RAG retrieval + parallel multi-agent orchestration
├── report.R                        # Report generation (multi-agent + fallback), HTML rendering
├── ui.R                            # Shiny UI definition
├── server.R                        # Shiny server logic
├── fetch_financials.R              # Yahoo Finance financial data fetcher
├── install_packages.R              # R package installer
├── Dockerfile                      # Docker config (rocker/shiny:4.4.0)
├── .env                            # API keys (gitignored)
├── .gitignore
├── historical_prices.csv           # Exported price data for RAG
├── model_parameters.csv            # Exported model params for RAG
├── key_financials.csv              # Key financial snapshot for RAG
├── company_financials.csv          # Multi-year P&L and credit for RAG
├── valuation_metrics.csv           # Multi-year valuation for RAG
├── news_archive.csv                # Accumulated news archive for RAG
├── rag_data_column_dictionary.csv  # Column definitions for model_parameters
└── data/                           # Local cache (gitignored)
    ├── daily_prices.csv
    ├── news.csv
    └── rag_history.csv
```

---

## API Rate Limits

| API | Limit | Usage |
|-----|-------|-------|
| Finnhub | 60 req/min (free) | Quotes, candles, news |
| Yahoo Finance | Unofficial, no key | Fallback for historical data |
| OpenAI | Per-plan | AI predictions, reports |
| Ollama | Unlimited (local) | Fallback LLM |

---

## Tech Stack

- **R / Shiny** — reactive web framework
- **Plotly** — interactive charts
- **DT** — data tables
- **httr2** — HTTP client for API calls
- **Docker** — containerized deployment
- **DigitalOcean App Platform** — cloud hosting
