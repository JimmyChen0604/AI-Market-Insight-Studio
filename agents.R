# agents.R
# Parallel multi-agent orchestration for equity research reports

# ----------------------------
# Date-aware preamble injected into every agent prompt
# ----------------------------

agent_date_preamble <- function() {
  paste0(
    "TODAY'S DATE: ", format(Sys.Date(), "%B %d, %Y"), ".\n",
    "CRITICAL RULES:\n",
    "- ALL financial data provided is HISTORICAL (already reported). Treat every number as a PAST result, not a forecast.\n",
    "- When referencing fiscal years, use PAST TENSE (e.g., 'FY2025 revenue was $X', NOT 'FY2025 revenue is projected').\n",
    "- Do NOT fabricate forward-looking projections. You may describe the TRAJECTORY implied by historical trends, but label it clearly as a trend extrapolation.\n",
    "- Do NOT invent numbers, targets, or events not present in the data.\n",
    "- Cite data exactly as given. If the data shows weakness, acknowledge it honestly.\n"
  )
}

# ----------------------------
# Agent role definitions
# ----------------------------

AGENT_ROLES <- list(
  fundamentals = list(
    name = "Fundamentals Analyst",
    system = paste0(
      "You are a senior equity fundamentals analyst at a top-tier investment bank.\n\n",
      "Analyze the historical financial data provided. ",
      "Evaluate: P/E vs forward P/E (expansion or compression), P/B, ROE trends across fiscal years, ",
      "revenue growth trajectory and whether it is accelerating or decelerating, ",
      "gross/EBITDA/net margin expansion or compression year-over-year, ",
      "balance sheet strength (debt-to-equity trend, net debt position), FCF generation and capex intensity, ",
      "and dividend sustainability.\n",
      "Also consider any recent company or macro news provided and how it may affect the fundamental outlook.\n\n",
      "All fiscal year data is HISTORICAL. Reference years in past tense.\n\n",
      "Return JSON with EXACTLY these keys:\n",
      "- fundamentals_summary: 8-12 sentences of substantive analysis citing specific numbers from the data\n",
      "- valuation_assessment: one of 'Significantly Undervalued', 'Undervalued', 'Fair Value', 'Overvalued', 'Significantly Overvalued' followed by 3-4 sentences of reasoning\n",
      "- financial_health_score: integer 0-100 (100 = pristine balance sheet, strong margins, high ROE)"
    )
  ),

  news = list(
    name = "News Analyst",
    system = paste0(
      "You are a senior news and macro analyst at a global investment research firm.\n\n",
      "You receive two types of news: company-specific headlines and MACRO/geopolitical headlines (marked Symbol='MACRO').\n",
      "Analyze both. For company news: identify earnings, guidance, M&A, product launches, regulatory actions.\n",
      "For macro news: identify tariff policies, interest rate changes, trade wars, geopolitical tensions, inflation data, ",
      "and assess how these macro factors specifically impact this company (e.g., supply chain exposure, revenue geography, cost structure).\n\n",
      "Only reference events that appear in the provided news data. Do not invent news.\n\n",
      "Return JSON with EXACTLY these keys:\n",
      "- news_sentiment: one of 'Very Positive', 'Positive', 'Mixed', 'Negative', 'Very Negative'\n",
      "- key_events: JSON array of 3-5 most impactful events (each 1-2 sentences)\n",
      "- macro_impact: 4-6 sentences on how macro environment affects this stock specifically"
    )
  ),

  technical = list(
    name = "Technical / Quantitative Analyst",
    system = paste0(
      "You are a senior quantitative analyst specializing in statistical modeling of equity returns.\n\n",
      "Interpret the model outputs provided:\n",
      "- GBM: drift mu (annualized expected return), sigma (annualized volatility), and their confidence intervals\n",
      "- Binomial Lattice (RWPM): up factor u, down factor d, real-world probability p_real, risk-neutral probability p_rn\n",
      "- Single Index Model vs SPY: beta (systematic risk), alpha (excess return), R-squared (market dependence), residual std (idiosyncratic risk)\n",
      "- Volatility: realized vs downside vs 20-day, skewness, kurtosis, max drawdown, normality test results\n",
      "Also interpret price momentum from the recent price changes provided.\n\n",
      "These are all computed from HISTORICAL data. State observations in past/present tense, not as predictions.\n\n",
      "Return JSON with EXACTLY these keys:\n",
      "- technical_signal: one of 'Strong Bullish', 'Bullish', 'Neutral', 'Bearish', 'Strong Bearish'\n",
      "- model_interpretation: 8-12 sentences interpreting the quant models, citing specific parameter values\n",
      "- momentum_summary: 3-5 sentences on price momentum and volatility regime"
    )
  ),

  bull = list(
    name = "Bull Researcher",
    system = paste0(
      "You are a bull researcher building the optimistic investment case.\n\n",
      "STRICT RULES:\n",
      "- Base your thesis ONLY on the historical data provided. Do NOT fabricate future projections or invent revenue/earnings numbers.\n",
      "- If the data shows deteriorating metrics (declining revenue, shrinking margins, rising debt), you MUST acknowledge these realities. Do not pretend weakness is strength.\n",
      "- You may highlight genuine positives: improving trends, strong margins vs peers, healthy FCF, low debt, growth acceleration, positive news catalysts from the provided data.\n",
      "- For upside_target, derive it from the CURRENT price and the historical growth/momentum data \u2014 do not invent a number.\n",
      "- All fiscal year references must be in PAST TENSE (this data is historical).\n\n",
      "Return JSON with EXACTLY these keys:\n",
      "- bull_thesis: 5-7 sentences building the optimistic case, citing specific historical data points\n",
      "- catalysts: JSON array of 3-4 specific catalysts grounded in the provided data or news\n",
      "- upside_target: a number (bull-case price target derived from data)"
    )
  ),

  bear = list(
    name = "Bear Researcher",
    system = paste0(
      "You are a bear researcher building the pessimistic investment case.\n\n",
      "STRICT RULES:\n",
      "- Base your thesis ONLY on the historical data and news provided. Do NOT fabricate scenarios not supported by data.\n",
      "- If the data shows strong metrics (growing revenue, expanding margins, low debt), you MUST acknowledge these realities. Focus on genuine vulnerabilities: valuation stretch, decelerating growth, margin compression, rising capex, competitive threats implied by the data.\n",
      "- Consider macro/geopolitical risks from the news (tariffs, trade policy, regulation) and how they specifically threaten this company.\n",
      "- For downside_target, derive it from the CURRENT price and historical risk metrics \u2014 do not invent a number.\n",
      "- All fiscal year references must be in PAST TENSE (this data is historical).\n\n",
      "Return JSON with EXACTLY these keys:\n",
      "- bear_thesis: 5-7 sentences building the pessimistic case, citing specific historical data points\n",
      "- risks: JSON array of 3-4 specific risk factors (each 1-2 sentences) grounded in the data\n",
      "- downside_target: a number (bear-case price target derived from data)"
    )
  ),

  risk = list(
    name = "Risk Manager",
    system = paste0(
      "You are the Chief Risk Officer evaluating this equity position.\n\n",
      "Assess using the HISTORICAL data provided: systematic risk (beta exposure to SPY), ",
      "volatility regime (realized vs 20-day \u2014 is vol expanding or contracting?), ",
      "tail risk (kurtosis, max drawdown, non-normality), ",
      "liquidity risk (average volume), leverage risk (debt-to-equity, net debt), ",
      "concentration risk, and idiosyncratic risk (SIM residual std, R-squared).\n",
      "Also assess geopolitical/macro risks from the news provided (tariffs, trade wars, regulatory changes) and how they affect this specific company.\n\n",
      "Return JSON with EXACTLY these keys:\n",
      "- risk_level: one of 'Low', 'Medium', 'High', 'Very High'\n",
      "- risk_factors: JSON array of 5-6 specific risk factors (each 2-3 sentences with numbers from the data)\n",
      "- risk_score: integer 0-100 (100 = extreme risk)"
    )
  )
)

PM_SYSTEM_PROMPT <- paste0(
  "You are the Portfolio Manager at a top-tier investment firm. ",
  "You have received analysis from six specialized analysts. ",
  "Your job is to SYNTHESIZE all their inputs into a final, cohesive equity research report.\n\n",
  "You must weigh: the fundamentals analyst's valuation assessment, the news analyst's sentiment reading, ",
  "the technical analyst's model signals, the bull and bear researchers' opposing cases, ",
  "and the risk manager's risk assessment. Resolve contradictions with reasoning.\n\n",
  "CRITICAL RULES:\n",
  "- Write at institutional quality. Every paragraph must be SUBSTANTIVE with SPECIFIC data references from the analyst outputs.\n",
  "- Do NOT write generic filler.\n",
  "- All financial data referenced is HISTORICAL. Use past tense for fiscal year results.\n",
  "- Do NOT fabricate forward projections. You may describe implied trends.\n\n",
  "Return JSON with EXACTLY these keys:\n",
  "- purchase_rating: one of 'Strong Buy', 'Buy', 'Hold', 'Sell', 'Fully Valued'\n",
  "- confidence: integer 0-100\n",
  "- key_reason: 3-4 sentences explaining PRIMARY drivers, referencing specific metrics from analyst reports\n",
  "- industry_analysis: 10-15 sentences covering sector overview, competitive landscape, company moat, ",
  "technology advantages, revenue drivers, barriers to entry, regulatory environment\n",
  "- investment_overview: 10-15 sentences covering valuation assessment, price momentum, quant model interpretation, ",
  "beta exposure, volatility regime, earnings quality, balance sheet strength, dividend policy, peer comparison\n",
  "- risk_analysis: JSON array of 5-6 STRINGS, each string is one specific risk factor (2-3 sentences). Example: [\"Risk factor one text...\", \"Risk factor two text...\"]. Do NOT use objects, only plain strings.\n",
  "- bull_case: 4-5 sentences from the bull researcher's thesis with catalysts and upside target\n",
  "- bear_case: 4-5 sentences from the bear researcher's thesis with risks and downside target\n",
  "- target_price_3m: number (your 3-month price target)\n",
  "- risk_level: one of 'Low', 'Medium', 'High', 'Very High'\n",
  "- forecast_trend: one of 'UP', 'DOWN', 'NEUTRAL'"
)

# ----------------------------
# Retrieve relevant CSV data for each agent
# ----------------------------

rag_retrieve <- function(symbol, agent_type) {
  app_dir <- get_export_dir()
  read_csv_safe <- function(filename) {
    path <- file.path(app_dir, filename)
    if (!file.exists(path)) return(NULL)
    tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
  }

  filter_ticker <- function(df, col = "ticker") {
    if (is.null(df) || nrow(df) == 0) return(NULL)
    if (col %in% names(df)) df[df[[col]] == symbol, , drop = FALSE]
    else if ("Symbol" %in% names(df)) df[df$Symbol == symbol, , drop = FALSE]
    else df
  }

  get_news <- function(n_company = 10, n_macro = 8) {
    all_news <- read_csv_safe("news_archive.csv")
    if (is.null(all_news) || !("Symbol" %in% names(all_news))) return(NULL)
    cols <- intersect(c("Symbol", "Title", "Source", "Published", "Summary"), names(all_news))
    if ("Published" %in% names(all_news)) all_news <- all_news[order(all_news$Published, decreasing = TRUE), ]

    company_news <- all_news[all_news$Symbol == symbol, cols, drop = FALSE]
    company_news <- head(company_news, n_company)

    macro_news <- all_news[all_news$Symbol == "MACRO", cols, drop = FALSE]
    macro_news <- head(macro_news, n_macro)

    combined <- dplyr::bind_rows(company_news, macro_news)
    if (nrow(combined) == 0) return(NULL)
    combined
  }

  switch(agent_type,
    fundamentals = {
      kf <- filter_ticker(read_csv_safe("key_financials.csv"))
      cf <- filter_ticker(read_csv_safe("company_financials.csv"))
      vm <- filter_ticker(read_csv_safe("valuation_metrics.csv"))
      if (!is.null(cf)) {
        cf <- cf[order(cf$fiscal_year_end), ]
        n <- nrow(cf)
        if (n > 4) cf <- cf[(n - 3):n, ]
      }
      if (!is.null(vm) && nrow(vm) > 4) {
        vm <- vm[order(vm$fiscal_year), ]
        vm <- vm[(nrow(vm) - 3):nrow(vm), ]
      }
      news <- get_news(8, 5)
      jsonlite::toJSON(list(
        key_financials = kf, company_financials = cf, valuation_metrics = vm,
        recent_news = news
      ), auto_unbox = TRUE, na = "null")
    },

    news = {
      news <- get_news(15, 10)
      if (is.null(news)) return("{\"news\": \"No recent news available.\"}")
      jsonlite::toJSON(list(news_headlines = news), auto_unbox = TRUE, na = "null")
    },

    technical = {
      mp <- filter_ticker(read_csv_safe("model_parameters.csv"))
      if (!is.null(mp) && nrow(mp) > 0) {
        mp <- mp[order(mp$snapshot_date, decreasing = TRUE), ]
        mp <- mp[1, , drop = FALSE]
      }
      hp <- filter_ticker(read_csv_safe("historical_prices.csv"), col = "Symbol")
      if (!is.null(hp) && nrow(hp) > 0) {
        hp <- hp[order(hp$Date, decreasing = TRUE), ]
        hp <- head(hp, 30)
      }
      dict <- read_csv_safe("rag_data_column_dictionary.csv")
      jsonlite::toJSON(list(
        model_parameters = mp, recent_prices = hp, column_dictionary = dict
      ), auto_unbox = TRUE, na = "null")
    },

    bull = {
      kf <- filter_ticker(read_csv_safe("key_financials.csv"))
      cf <- filter_ticker(read_csv_safe("company_financials.csv"))
      if (!is.null(cf)) {
        cf <- cf[order(cf$fiscal_year_end), ]
        n <- nrow(cf)
        if (n > 4) cf <- cf[(n - 3):n, ]
      }
      news <- get_news(10, 5)
      jsonlite::toJSON(list(
        key_financials = kf, company_financials = cf, recent_news = news
      ), auto_unbox = TRUE, na = "null")
    },

    bear = {
      kf <- filter_ticker(read_csv_safe("key_financials.csv"))
      cf <- filter_ticker(read_csv_safe("company_financials.csv"))
      if (!is.null(cf)) {
        cf <- cf[order(cf$fiscal_year_end), ]
        n <- nrow(cf)
        if (n > 4) cf <- cf[(n - 3):n, ]
      }
      mp <- filter_ticker(read_csv_safe("model_parameters.csv"))
      if (!is.null(mp) && nrow(mp) > 0) {
        mp <- mp[order(mp$snapshot_date, decreasing = TRUE), ]
        mp <- mp[1, , drop = FALSE]
        mp <- mp[, intersect(c("ticker", "vol_annual_realized", "max_drawdown",
                                "kurtosis", "sim_beta", "gbm_sigma_annual"), names(mp)), drop = FALSE]
      }
      news <- get_news(10, 8)
      jsonlite::toJSON(list(
        key_financials = kf, company_financials = cf, risk_indicators = mp,
        recent_news = news
      ), auto_unbox = TRUE, na = "null")
    },

    risk = {
      mp <- filter_ticker(read_csv_safe("model_parameters.csv"))
      if (!is.null(mp) && nrow(mp) > 0) {
        mp <- mp[order(mp$snapshot_date, decreasing = TRUE), ]
        mp <- mp[1, , drop = FALSE]
      }
      cf <- filter_ticker(read_csv_safe("company_financials.csv"))
      if (!is.null(cf)) {
        cf <- cf[order(cf$fiscal_year_end), ]
        n <- nrow(cf)
        if (n > 4) cf <- cf[(n - 3):n, ]
        cf <- cf[, intersect(c("fiscal_year", "debt_equity_pct", "net_debt_equity_pct",
                                "debt_assets_pct", "ebitda_int_exp", "debt_ebitda"), names(cf)), drop = FALSE]
      }
      news <- get_news(5, 8)
      jsonlite::toJSON(list(
        model_parameters = mp, credit_metrics = cf, recent_news = news
      ), auto_unbox = TRUE, na = "null")
    },

    "{}"
  )
}

# ----------------------------
# Build a single agent HTTP request (OpenAI)
# ----------------------------

build_agent_request <- function(system_prompt, user_content, api_key,
                                model = "gpt-4o-mini", max_tokens = 1500) {
  body <- list(
    model = model,
    temperature = 0,
    seed = 42L,
    messages = list(
      list(role = "system", content = system_prompt),
      list(role = "user", content = user_content)
    ),
    response_format = list(type = "json_object"),
    max_tokens = max_tokens
  )

  request("https://api.openai.com/v1/chat/completions") |>
    req_headers(
      Authorization = paste0("Bearer ", api_key),
      `Content-Type` = "application/json"
    ) |>
    req_body_json(body) |>
    req_timeout(60)
}

# ----------------------------
# Parse a single agent response
# ----------------------------

parse_agent_response <- function(resp) {
  if (!inherits(resp, "httr2_response")) return(NULL)
  if (resp_status(resp) != 200) {
    message("[Agent] HTTP ", resp_status(resp))
    return(NULL)
  }
  raw <- tryCatch(resp_body_json(resp), error = function(e) NULL)
  if (is.null(raw)) return(NULL)

  text <- raw$choices[[1]]$message$content
  if (is.null(text) || !nzchar(text)) return(NULL)

  text <- gsub("^```json|```$", "", trimws(text))
  tryCatch(jsonlite::fromJSON(text), error = function(e) {
    message("[Agent] JSON parse failed: ", e$message)
    NULL
  })
}

# ----------------------------
# Phase 1: Run 6 analyst agents in parallel
# ----------------------------

run_phase1_parallel <- function(symbol, company_name, sector, trend_text, api_key) {
  agent_types <- names(AGENT_ROLES)
  preamble <- agent_date_preamble()

  user_prompts <- lapply(agent_types, function(atype) {
    rag_context <- rag_retrieve(symbol, atype)
    paste0(
      preamble, "\n",
      "Analyze ", symbol, " (", company_name, "), sector: ", sector, ".\n\n",
      if (nzchar(trend_text)) paste0("=== PRICE CONTEXT ===\n", trend_text, "\n\n") else "",
      "=== HISTORICAL DATA ===\n", rag_context
    )
  })
  names(user_prompts) <- agent_types

  reqs <- lapply(agent_types, function(atype) {
    role <- AGENT_ROLES[[atype]]
    build_agent_request(
      system_prompt = role$system,
      user_content  = user_prompts[[atype]],
      api_key       = api_key,
      max_tokens    = 1500
    )
  })

  message("[Phase1] Sending ", length(reqs), " analyst requests in parallel...")
  resps <- tryCatch(
    req_perform_parallel(reqs, on_error = "continue"),
    error = function(e) {
      message("[Phase1] Parallel request failed: ", e$message)
      NULL
    }
  )
  if (is.null(resps)) return(NULL)

  outputs <- setNames(
    lapply(resps, parse_agent_response),
    agent_types
  )

  ok_count <- sum(!vapply(outputs, is.null, logical(1)))
  message("[Phase1] ", ok_count, "/", length(agent_types), " analysts returned valid responses")
  outputs
}

# ----------------------------
# Phase 2: Portfolio Manager synthesizes all agent outputs
# ----------------------------

run_phase2_pm <- function(symbol, company_name, sector, agent_outputs, api_key) {
  preamble <- agent_date_preamble()

  summary_parts <- lapply(names(agent_outputs), function(atype) {
    out <- agent_outputs[[atype]]
    if (is.null(out)) return(paste0("## ", AGENT_ROLES[[atype]]$name, "\n[Analysis unavailable]\n"))
    paste0(
      "## ", AGENT_ROLES[[atype]]$name, "\n",
      jsonlite::toJSON(out, auto_unbox = TRUE, pretty = TRUE), "\n"
    )
  })

  pm_user <- paste0(
    preamble, "\n",
    "Produce the final equity research report for ", symbol, " (", company_name, "), sector: ", sector, ".\n\n",
    "Below are the analysis outputs from your six specialist analysts:\n\n",
    paste(summary_parts, collapse = "\n"),
    "\n\nSynthesize all inputs into your final recommendation. ",
    "Resolve any contradictions between bull/bear cases with your professional judgment. ",
    "Ensure every section references specific data from the analyst reports."
  )

  message("[Phase2] Sending Portfolio Manager synthesis request...")
  pm_req <- build_agent_request(
    system_prompt = PM_SYSTEM_PROMPT,
    user_content  = pm_user,
    api_key       = api_key,
    max_tokens    = 4000
  )

  pm_resp <- tryCatch(req_perform(pm_req), error = function(e) {
    message("[Phase2] PM request failed: ", e$message)
    NULL
  })

  parse_agent_response(pm_resp)
}

# ----------------------------
# Orchestrator: Full parallel multi-agent pipeline
# ----------------------------

run_parallel_agents <- function(symbol, stock_data_val, news_data_df,
                                trend = NULL, gbm = NULL, lattice = NULL, sim = NULL) {
  company_name <- TICKER_LABELS[[symbol]] %||% symbol
  sector <- SECTOR_MAP[[symbol]] %||% "Unknown"

  api_key <- Sys.getenv("OPENAI_API_KEY")
  if (!nzchar(api_key)) {
    return(list(ok = FALSE, error = "OPENAI_API_KEY not set."))
  }

  trend_text <- ""
  if (!is.null(trend)) {
    trend_text <- sprintf(
      "Current price: %s\n1-day change: %s\n7-day change: %s\n30-day change: %s\nAnnualized 20-day volatility: %s",
      fmt_price(trend$latest), fmt_pct(trend$change1d_pct),
      fmt_pct(trend$change7d_pct), fmt_pct(trend$change30d_pct),
      ifelse(is.na(trend$mean_20d_volatility), "N/A", paste0(trend$mean_20d_volatility, "%"))
    )
  }

  agent_outputs <- run_phase1_parallel(symbol, company_name, sector, trend_text, api_key)
  if (is.null(agent_outputs) || all(vapply(agent_outputs, is.null, logical(1)))) {
    message("[Agents] Phase 1 failed, falling back to single-call approach")
    return(NULL)
  }

  report <- run_phase2_pm(symbol, company_name, sector, agent_outputs, api_key)
  if (is.null(report)) {
    message("[Agents] Phase 2 failed, falling back to single-call approach")
    return(NULL)
  }

  report
}
