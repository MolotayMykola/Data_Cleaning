# Global Layoffs: Data Cleaning and Analysis in PostgreSQL
<img width="951" height="633" alt="dashboard" src="https://github.com/user-attachments/assets/2ae7277f-2957-4361-95e2-f3966c9c860b" />

An end-to-end SQL project: a raw CSV of company layoffs is cleaned in PostgreSQL, analyzed with SQL, and presented in a Power BI dashboard connected directly to the database. Despite the dataset's name, it covers layoffs from 2020 to September 23, 2026.

**Headline findings** (events with a reported headcount: 932,322 people):
- 2023 was the peak: 265,660 people in 1,390 events.
- The US accounts for 70.9% of reported layoffs; five companies (Amazon, Intel, Meta, Microsoft, Dell) make up 21%.
- Layoff size grows with company maturity: the median event is ~30 people at Seed and ~200 at post-IPO companies.

**Tools:** PostgreSQL 18, pgAdmin, Power BI
**Dataset:** [Global Layoffs on Kaggle](https://www.kaggle.com/datasets/swaptr/layoffs-2022)
**Cleaning:** [`layoffs_cleaning.sql`](layoffs_cleaning.sql)
**Analysis:** [`exploration.sql`](exploration.sql)

## Approach
- The raw table `layoffs` is never modified. All work happens in a copy, `layoffs_staging`.
- The script is re-runnable: it rebuilds the staging table from the raw one, then applies every step in order.
- Each risky change (duplicate removal, type conversion, bulk updates) is previewed with a `SELECT` before it is applied.

## Problems found and how they were solved
| # | Problem | Solution |
|---|---|---|
| 1 | Two duplicate rows | `ROW_NUMBER()` over all event columns in a CTE, then `DELETE` by `ctid` (the table has no primary key) |
| 2 | `date` stored as text (`MM/DD/YYYY`) | Parse check with `TO_DATE()`, then `ALTER COLUMN ... TYPE DATE USING TO_DATE(...)` |
| 3 | 9 company names written with different letter case (UiPath / UIPath, TikTok / Tiktok, ...) | Found with a self-join on `LOWER()`, fixed one by one. `INITCAP()` was rejected because it breaks brand names (UiPath becomes Uipath) |
| 4 | `UAE` and `United Arab Emirates` used for the same country (10 rows) | Unified to the full name, consistent with the rest of the country list |
| 5 | NULLs in `location` (1), `industry` (2), `country` (2), `stage` (8) | Restored from other columns, other rows or public information where possible; otherwise marked `Unknown` (see decisions below) |
| 6 | `percentage_laid_off` stored as text with float noise (`0.7000000000000001`) | Converted to `NUMERIC` and rounded to 4 decimals |
| 7 | Columns not useful for analysis (`source` URLs, `date_added` metadata) | Dropped from the staging table |

## Decisions worth explaining
- **Logistics and Transportation stay separate.** I checked whether any company appears in both categories: none does, so there is no evidence of a naming duplicate. Merging them would be a guess.
- **`stage` for Zapp.** One Zapp row had no stage, another had `Series B`. `funds_raised` is identical in both rows, so no new funding round happened between them, and the stage was copied across. The other seven missing stages belong to companies that appear only once, so they were marked `Unknown`.
- **`industry` for Appsmith and Eyeo.** Neither company appears elsewhere in the table. I chose the closest existing categories (`Infrastructure` and `Other`) instead of inventing new ones. This is a judgement call, flagged in the script.
- **Country restored from location** for two companies (Berlin: Germany, Montreal: Canada).
- **Genuinely unknown values stay NULL:** `total_laid_off` (1,600 rows, 34.7%), `percentage_laid_off` (1,728 rows, 37.5%) and `funds_raised` (550 rows, 11.9%). The sources did not report them, and filling them in would invent data.
- **748 rows with no layoff figures at all (16.2%) are kept.** They still record that a layoff event happened. Analyses of layoff size should filter with `WHERE total_laid_off IS NOT NULL`.

## Before and after
| | Raw | Cleaned |
|---|---|---|
| Rows | 4,615 | 4,613 |
| Duplicates | 2 | 0 |
| `date` type | text | `date` |
| `percentage_laid_off` type | text | `numeric` |
| NULLs in `location`, `industry`, `stage`, `country` | 1, 2, 8, 2 | 0, 0, 0, 0 |
| Case-variant company names | 9 pairs | 0 |
                                                                
Raw Data <img width="1280" height="167" alt="image" src="https://github.com/user-attachments/assets/dcfa5eb6-fb19-431a-afbd-092c65d6bd30" />
Cleaned Data<img width="1280" height="171" alt="image" src="https://github.com/user-attachments/assets/b412c6db-eab3-40e1-bb53-bd5026911ab0" />

## Key findings
*Based on the 3,013 events (65%) that report a headcount: 932,322 people in total.*

- **2023 was the peak:** 265,660 people in 1,390 events. January 2023 alone was 89,709 (34% of that year).
- **Fewer but bigger events since:** from 2023 to 2025 events fell 76%, people only 54%. 2026 (to Sep 23) already exceeds all of 2025.
- **A few giants dominate:** five companies (Amazon, Intel, Meta, Microsoft, Dell) make up 21.2% of all layoffs; each leading industry is driven by one or two firms.
- **Geography:** the US accounts for 70.91%, India 7.28% (spread across many companies, not a few), the top 10 countries ~94.5%.
- **Layoff size grows with company maturity:** the median event is ~30 people at Seed/Series A, 48-96 at Series B-E and about 200 at post-IPO companies (overall median: 90). Post-IPO averages are inflated by a few giants, but even the median is more than double the overall one.

Queries and notes: [exploration.sql](exploration.sql)

## SQL techniques used
CTEs, window functions (`ROW_NUMBER`, `RANK`, `LAG`), self-joins, `ctid`-based deletes, `ALTER TABLE ... USING`, `FILTER` in aggregates, `STRING_AGG`, `PERCENTILE_CONT` (median), `DATE_TRUNC`, `TO_DATE`, `ROUND`, `TRIM`.

## Lessons learned
- Inspect the CSV header before creating the table: the real column order differed from what I assumed, and the import failed several times (wrong column count, `96.0` in an integer column, URLs longer than the declared length).
- Drop columns you will not analyze (long URLs especially) right after creating the staging table; they make `SELECT *` hard to read.
- Standardizing text can reveal new duplicates, so the duplicate check runs again at the end.
- When ranking within an industry, group by company and industry together: industry is recorded per event, so summing by company alone double-counted companies that appear in two categories.
  
## How to run
1. Create the database and run STEP 0 of the script to create the `layoffs` table.
2. Import the CSV in pgAdmin (Import/Export Data, Header = Yes, Delimiter = comma).
3. Run the rest of the script top to bottom, or one step at a time.
