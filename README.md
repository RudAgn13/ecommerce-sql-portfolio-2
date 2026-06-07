# CartIQ E-Commerce SQL Analytics Portfolio

> End-to-end SQL analytics across a synthetic multi-category e-commerce platform.
> Built to demonstrate the analytical depth expected at growth-stage e-commerce companies.

---

## Database

- **Platform:** PostgreSQL 15
- **Tables:** 10 (customers, orders, order_items, products, categories, sellers, payments, returns, marketing_events, customer_sessions)
- **Scale:** ~860 seed rows (representative sample; production scale ~1.7M rows via generation script)

---

## Projects

| # | Folder | Focus | Key Metrics |
|---|--------|-------|-------------|
| 01 | `01_customer_lifecycle_analysis` | Retention & Segmentation | LTV, RFM, Cohort Retention, Churn Signals |
| 02 | `02_revenue_and_margin_intelligence` | P&L Analytics | GMV vs Net Revenue, Contribution Margin, Discount Depth, MoM Growth |
| 03 | `03_supply_chain_and_ops_health` | Operations | OTDR, Return Root Cause, Payment Failures, Fulfillment Funnel |
| 04 | `04_marketing_and_acquisition_roi` | Growth & Spend | CAC by Channel, Email Funnel, UTM Attribution |
| 05 | `05_seller_and_category_performance` | Marketplace Health | Seller Scorecard, Category Velocity, Repeat Purchase Rate |

---

## SQL Concepts

Window functions (`NTILE`, `ROW_NUMBER`, `LAG`, `RANK`), multi-level CTEs, conditional aggregation, cohort analysis, funnel analysis, composite scoring, attribution modelling, date arithmetic, `NULLIF` safe division, ordered-set aggregates (`MODE()`), nested window functions.

---

## How to Run

See `/schema/README.md` for setup instructions.

---

## Transparency Note

All SQL queries, analytical logic, business reasoning, and inline code comments are written entirely by the author. The database schema and seed data were designed and built by the author.

The comment block headers above each metric in the query files — covering business context, design notes, and key output columns — were written with AI assistance (Claude by Anthropic) for documentation quality and clarity. The README files for each project were similarly AI-assisted in structure and prose.

This distinction is noted to set accurate expectations: the analytical thinking, every line of SQL, and all decisions about what to measure and why are fully human-driven. The AI's role was documentation and formatting only.
