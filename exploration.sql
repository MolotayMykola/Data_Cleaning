-- =====================================================================
-- Global Layoffs: exploratory analysis on the cleaned table
-- Source table: layoffs_staging (built by layoffs_cleaning.sql)
--
-- Important context for every query below:
--   * total_laid_off is known for 3,013 of 4,613 events (65.3%),
--     932,322 people in total. Queries about size filter on
--     total_laid_off IS NOT NULL; COUNT(*) counts all events.
--   * Data ends on 2026-09-23, so 2026 and September 2026 are incomplete.
-- =====================================================================


-- Q1: Which industries lost the most people?
SELECT industry, SUM(total_laid_off) AS layoffs_by_industry
FROM layoffs_staging
WHERE total_laid_off IS NOT NULL
GROUP BY industry
ORDER BY layoffs_by_industry DESC;

-- Insight: "Other" tops the list (116,665) but it is a catch-all category;
-- Microsoft alone is ~30% of it. Among named industries Retail (108,495),
-- Hardware (105,532) and Consumer (98,654) lead, and each is dominated by
-- giants: Amazon = 55% of Retail, Intel + Dell = 63% of Hardware,
-- Meta = 36% of Consumer.


-- Q2: How many layoff events and how many people per year?
SELECT DATE_TRUNC('year', "date")::date AS "year", SUM(total_laid_off) AS layoff_by_year, COUNT(*) AS events_number
FROM layoffs_staging
GROUP BY "year"
ORDER BY "year" DESC;

-- Insight: layoffs peaked in 2023 (265,660 people, 1,390 events). From 2023
-- to 2025 events fell 76% (1,390 -> 333) while people fell only 54%
-- (265,660 -> 122,606): fewer but larger events. 2026 is incomplete (data
-- ends Sep 23) yet already exceeds full-year 2025 (129,994 vs 122,606 people).
-- Notes: event counts include events with no reported headcount; 2021 has
-- only 44 events, which looks like thin source coverage rather than a real
-- lull (not verified).


-- Q3: Top 5 companies by total people laid off
SELECT company, SUM(total_laid_off) AS company_laid_off
FROM layoffs_staging
WHERE total_laid_off IS NOT NULL
GROUP BY company
ORDER BY company_laid_off DESC
LIMIT 5;

-- Insight: five companies (Amazon 59,560; Intel 43,167; Meta 35,700;
-- Microsoft 35,355; Dell 23,650) account for 21.2% of all reported layoffs;
-- Amazon alone is 6.4%.


-- Q4: Top 3 companies by people laid off in each industry
-- Grouped by company AND industry: industry is recorded per event, so one
-- company can appear in several industries (e.g. OneTrust: 150 in Legal,
-- 950 in Security). Ties share a rank (Legal has two companies at rank 2).
WITH company_totals AS (
	SELECT company, industry, SUM(total_laid_off) AS company_laid_off
	FROM layoffs_staging
	GROUP BY company, industry
), ranked AS (
	SELECT *, RANK() OVER(PARTITION BY industry ORDER BY company_laid_off DESC) AS ranking
	FROM company_totals
	WHERE company_laid_off IS NOT NULL
)
SELECT *
FROM ranked
WHERE ranking <= 3
ORDER BY industry, ranking;

-- Insight: in most industries one company dominates. Amazon is ~55% of
-- Retail (59,560 of 108,495), Cisco ~74% of Infrastructure (18,521 of
-- 24,870), Salesforce ~75% of Sales (16,744 of 22,181) and Intel + Dell
-- ~63% of Hardware.


-- Q5: Month-over-month percentage change in people laid off
WITH month_splitting AS (
	SELECT DATE_TRUNC('month', "date")::date AS "month", SUM(total_laid_off) AS sum_laid_off
	FROM layoffs_staging
	WHERE total_laid_off IS NOT NULL
	GROUP BY "month"
), added_lag_row AS (
	SELECT *, LAG(sum_laid_off) OVER(ORDER BY "month") AS lag_column
	FROM month_splitting
)
SELECT *, ROUND(100.0 * (sum_laid_off - lag_column) / lag_column, 2) AS pct_change
FROM added_lag_row
WHERE lag_column IS NOT NULL
ORDER BY "month";

-- Insight: percentage changes are dominated by small bases (+9,309% in
-- Nov 2021 means 22 -> 2,070 people), so volumes matter more. The largest
-- months: Jan 2023 (89,709, 34% of that year), Nov 2022 (53,594) and
-- Feb 2023 (40,002). January exceeded the previous December in 4 of 6 years
-- (2021, 2023, 2024, 2026).
-- Caveats: May 2021 has no rows with figures, so LAG compares Apr with Jun;
-- Sep 2026 is incomplete.


-- Q6: Companies that laid off 100% of staff: which industries and stages?
SELECT industry, COUNT(DISTINCT company) AS companies
FROM layoffs_staging
WHERE percentage_laid_off = 1
GROUP BY industry
ORDER BY companies DESC
LIMIT 5;

SELECT stage, COUNT(DISTINCT company) AS companies
FROM layoffs_staging
WHERE percentage_laid_off = 1
GROUP BY stage
ORDER BY companies DESC
LIMIT 5;

-- No insight drawn: these are raw counts without a denominator. An industry
-- or stage may lead simply because it has the most companies overall.
-- (Unknown stage is a placeholder from cleaning, not a real category.)


-- Q7: Share of reported layoffs by country
WITH country_laid_off AS (
	SELECT *, SUM(total_laid_off) OVER(PARTITION BY country) AS by_country
	FROM layoffs_staging
), filtered AS (
	SELECT DISTINCT country,
		ROUND(100.0 * by_country / (SELECT SUM(total_laid_off) FROM layoffs_staging), 2) AS countrypart_from_total
	FROM country_laid_off
)
SELECT *
FROM filtered
WHERE countrypart_from_total IS NOT NULL
ORDER BY countrypart_from_total DESC;

-- Is India's share driven by a few companies?
SELECT company, SUM(total_laid_off) AS laid_off
FROM layoffs_staging
WHERE country = 'India' AND total_laid_off IS NOT NULL
GROUP BY company
ORDER BY laid_off DESC
LIMIT 40;

-- Insight: the US accounts for 70.91% of reported layoffs, India 7.28% and
-- Germany 3.45%; the top 10 countries cover ~94.5%. India's share is broad,
-- not driven by one or two firms: 15 Indian companies reported 1,000+ each,
-- led by Byju's (5,500) and Paytm (5,400).
-- Shares cover only events with a known headcount.


-- Q8: How does layoff size (people per event) vary by funding stage?
-- Stages with fewer than 10 events with figures are excluded (too small).
SELECT stage,
	COUNT(total_laid_off) AS events_with_figures,
	ROUND(AVG(total_laid_off), 2) AS avg_size,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_laid_off) AS median_size
FROM layoffs_staging
GROUP BY stage
HAVING COUNT(total_laid_off) >= 10
ORDER BY median_size DESC;

-- Overall median event size, for comparison (90 people)
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_laid_off) AS overall_median
FROM layoffs_staging;

-- Insight: layoff size grows with company maturity. The median event is
-- ~30 people at Seed/Series A (29.5, 32.5), 48-96 at Series B-E and 185-250
-- at Series H-J, with 200 at Post-IPO (794 events), against an overall
-- median of 90. Post-IPO's mean (737) is inflated by a few giants (3.7x its
-- median), but its median is still more than twice the overall one, so a
-- typical public-company event really is larger. Series J (11 events) has
-- the highest median but a very small sample. Unknown stage (473 events)
-- mixes companies of all sizes.
