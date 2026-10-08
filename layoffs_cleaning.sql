-- =====================================================================
-- Global Layoffs: data cleaning in PostgreSQL
-- Dataset: https://www.kaggle.com/datasets/swaptr/layoffs-2022
--
-- Approach:
--   * the raw table `layoffs` is never modified
--   * all cleaning happens in the working copy `layoffs_staging`
--   * the script is re-runnable: STEP 1 rebuilds staging from the raw table
-- =====================================================================


-- =====================================================================
-- STEP 0: Raw table (run once, then import layoffs.csv)
-- Import in pgAdmin: right-click the table -> Import/Export Data
--   (Header = Yes, Delimiter = comma).
-- Dates and percentages are loaded as text on purpose: source dates are
-- MM/DD/YYYY and percentages contain float noise (e.g. 0.7000000000000001).
-- They are converted to proper types in STEP 4 and STEP 7.
-- =====================================================================
CREATE TABLE IF NOT EXISTS layoffs (
	company VARCHAR(100),
	location VARCHAR(100),
	total_laid_off NUMERIC,
	date VARCHAR(20),
	percentage_laid_off VARCHAR(50),
	industry VARCHAR(100),
	source TEXT,
	stage VARCHAR(50),
	funds_raised NUMERIC,
	country VARCHAR(100),
	date_added VARCHAR(20)
);

SELECT COUNT(*) FROM layoffs;  -- baseline: 4615 rows


-- =====================================================================
-- STEP 1: Staging copy
-- =====================================================================
DROP TABLE IF EXISTS layoffs_staging;
CREATE TABLE layoffs_staging AS TABLE layoffs;


-- =====================================================================
-- STEP 2: Drop columns not needed for analysis
-- `source` (long URLs) and `date_added` (metadata about when the row was
-- added to the dataset, not about the layoff event itself).
-- Dropped early so they do not clutter SELECT * output.
-- =====================================================================
ALTER TABLE layoffs_staging DROP COLUMN source;
ALTER TABLE layoffs_staging DROP COLUMN date_added;


-- =====================================================================
-- STEP 3: Remove duplicates
-- ctid is the physical row address in PostgreSQL; it lets us delete exactly
-- one of several identical rows when the table has no primary key.
-- =====================================================================

-- Preview: rows that would be deleted
WITH duplicates AS (
	SELECT ctid, ROW_NUMBER() OVER(
		PARTITION BY company, location, total_laid_off, "date",
			percentage_laid_off, industry, stage, funds_raised, country
	) AS row_num
	FROM layoffs_staging
)
SELECT * FROM layoffs_staging
WHERE ctid IN (SELECT ctid FROM duplicates WHERE row_num > 1);

-- Delete (2 rows in this dataset)
WITH duplicates AS (
	SELECT ctid, ROW_NUMBER() OVER(
		PARTITION BY company, location, total_laid_off, "date",
			percentage_laid_off, industry, stage, funds_raised, country
	) AS row_num
	FROM layoffs_staging
)
DELETE FROM layoffs_staging
WHERE ctid IN (SELECT ctid FROM duplicates WHERE row_num > 1);

SELECT COUNT(*) FROM layoffs_staging;  -- expected: 4613


-- =====================================================================
-- STEP 4: Convert `date` from text (MM/DD/YYYY) to DATE
-- Checked first with a plain SELECT: all rows parse without errors.
-- Note: ALTER COLUMN TYPE rewrites the whole table and cannot be undone
-- without a backup; fine here (small table, raw copy still exists).
-- =====================================================================
SELECT TO_DATE("date", 'MM/DD/YYYY') FROM layoffs_staging;

ALTER TABLE layoffs_staging
	ALTER COLUMN "date" TYPE DATE USING TO_DATE("date", 'MM/DD/YYYY');

SELECT pg_typeof("date") FROM layoffs_staging LIMIT 1;


-- =====================================================================
-- STEP 5: Standardize text fields
-- =====================================================================

-- 5.1 Trim leading/trailing spaces in all text columns
UPDATE layoffs_staging
SET company = TRIM(company),
	location = TRIM(location),
	industry = TRIM(industry),
	country = TRIM(country),
	stage = TRIM(stage);

-- 5.2 Company names that differ only by letter case
-- Check: returns 18 rows (9 pairs, each shown in both directions)
SELECT DISTINCT a.company, b.company
FROM layoffs_staging a
JOIN layoffs_staging b
	ON LOWER(a.company) = LOWER(b.company)
	AND a.company != b.company
ORDER BY 1;

-- INITCAP() would break brand names (UiPath -> Uipath), so fixed one by one
UPDATE layoffs_staging SET company = 'AppGate' WHERE company = 'Appgate';
UPDATE layoffs_staging SET company = 'ClearCo' WHERE company = 'Clearco';
UPDATE layoffs_staging SET company = 'Loop' WHERE company = 'LOOP';
UPDATE layoffs_staging SET company = 'FreshBooks' WHERE company = 'Freshbooks';
UPDATE layoffs_staging SET company = 'UiPath' WHERE company = 'UIPath';
UPDATE layoffs_staging SET company = 'TikTok' WHERE company = 'Tiktok';
UPDATE layoffs_staging SET company = 'Mara' WHERE company = 'MARA';
UPDATE layoffs_staging SET company = 'SalesLoft' WHERE company = 'Salesloft';
UPDATE layoffs_staging SET company = '7shifts' WHERE company = '7Shifts';

-- Re-check: should return 0 rows
SELECT DISTINCT a.company, b.company
FROM layoffs_staging a
JOIN layoffs_staging b
	ON LOWER(a.company) = LOWER(b.company)
	AND a.company != b.company;

-- 5.3 Same check for the categorical columns (country shown here;
-- the identical pattern was run for industry, location and stage:
-- no differences found)
SELECT DISTINCT a.country, b.country
FROM layoffs_staging a
JOIN layoffs_staging b
	ON TRIM(LOWER(a.country)) = TRIM(LOWER(b.country))
	AND a.country != b.country;

-- 5.4 UAE and United Arab Emirates are the same country (3 + 7 rows)
SELECT country, COUNT(*)
FROM layoffs_staging
WHERE country IN ('United Arab Emirates', 'UAE')
GROUP BY country;

UPDATE layoffs_staging
SET country = 'United Arab Emirates'
WHERE country = 'UAE';

-- 5.5 Decision: Logistics and Transportation stay separate categories.
-- No company appears in both, so there is no evidence of a naming duplicate.
SELECT company, COUNT(DISTINCT industry) AS industry_count,
	STRING_AGG(DISTINCT industry, ', ') AS industries
FROM layoffs_staging
WHERE industry IN ('Logistics', 'Transportation')
GROUP BY company
HAVING COUNT(DISTINCT industry) > 1;  -- returns 0 rows

SELECT DISTINCT industry FROM layoffs_staging ORDER BY 1;
SELECT DISTINCT country FROM layoffs_staging ORDER BY 1;


-- =====================================================================
-- STEP 6: NULL values
-- =====================================================================

-- 6.1 NULL count per column
SELECT
	COUNT(*) FILTER(WHERE company IS NULL) AS company_null,
	COUNT(*) FILTER(WHERE location IS NULL) AS location_null,
	COUNT(*) FILTER(WHERE total_laid_off IS NULL) AS total_laid_off_null,
	COUNT(*) FILTER(WHERE "date" IS NULL) AS date_null,
	COUNT(*) FILTER(WHERE percentage_laid_off IS NULL) AS percentage_laid_off_null,
	COUNT(*) FILTER(WHERE industry IS NULL) AS industry_null,
	COUNT(*) FILTER(WHERE stage IS NULL) AS stage_null,
	COUNT(*) FILTER(WHERE funds_raised IS NULL) AS funds_raised_null,
	COUNT(*) FILTER(WHERE country IS NULL) AS country_null
FROM layoffs_staging;

-- 6.2 location: Product Hunt (single row, restored from public information)
UPDATE layoffs_staging
SET location = 'San Francisco, California'
WHERE company = 'Product Hunt' AND location IS NULL;

-- 6.3 industry: Appsmith and Eyeo (analyst judgement; no better-fitting
-- category in the existing list, each company appears only once)
UPDATE layoffs_staging SET industry = 'Other' WHERE company = 'Eyeo' AND industry IS NULL;
UPDATE layoffs_staging SET industry = 'Infrastructure' WHERE company = 'Appsmith' AND industry IS NULL;

-- 6.4 stage
-- Zapp: funds_raised is identical in both of its rows, so no new funding
-- round happened between them; the later row's stage applies to the earlier one.
SELECT company, "date", stage, funds_raised
FROM layoffs_staging
WHERE company = 'Zapp'
ORDER BY "date";

UPDATE layoffs_staging
SET stage = 'Series B'
WHERE company = 'Zapp' AND stage IS NULL;

-- Remaining companies appear only once, so the value cannot be restored:
-- mark as 'Unknown' (an existing category in the dataset)
UPDATE layoffs_staging
SET stage = 'Unknown'
WHERE stage IS NULL;

-- 6.5 country: restored from the city in `location`
SELECT company, location, industry, "date", country
FROM layoffs_staging
WHERE country IS NULL;

UPDATE layoffs_staging SET country = 'Germany' WHERE company = 'Fit Analytics' AND country IS NULL;  -- Berlin
UPDATE layoffs_staging SET country = 'Canada' WHERE company = 'Ludia' AND country IS NULL;           -- Montreal

-- 6.6 Intentionally left as NULL: total_laid_off, percentage_laid_off,
-- funds_raised (the sources simply did not report these values).
-- 748 rows have neither total_laid_off nor percentage_laid_off. They are
-- kept because they record that the layoff event happened; analyses of
-- layoff size should filter with WHERE total_laid_off IS NOT NULL.
SELECT COUNT(*) FROM layoffs_staging
WHERE total_laid_off IS NULL AND percentage_laid_off IS NULL;


-- =====================================================================
-- STEP 7: percentage_laid_off from text to NUMERIC
-- Values are fractions of 1 (0.7 = 70%). Rounded to 4 decimals to remove
-- float noise such as 0.7000000000000001 without losing real precision.
-- =====================================================================
SELECT percentage_laid_off::NUMERIC FROM layoffs_staging;  -- parse check

ALTER TABLE layoffs_staging
	ALTER COLUMN percentage_laid_off TYPE NUMERIC
	USING ROUND(percentage_laid_off::NUMERIC, 4);


-- =====================================================================
-- STEP 8: Final verification
-- =====================================================================

-- 8.1 Row count (4615 raw - 2 duplicates = 4613)
SELECT COUNT(*) FROM layoffs_staging;

-- 8.2 No duplicates left (standardization in STEP 5 can reveal new ones;
-- if this returns rows, re-run the DELETE from STEP 3)
SELECT company, location, total_laid_off, "date", percentage_laid_off,
	industry, stage, funds_raised, country, COUNT(*)
FROM layoffs_staging
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
HAVING COUNT(*) > 1;

-- 8.3 Data types of all columns
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'layoffs_staging'
ORDER BY ordinal_position;

-- 8.4 Remaining NULLs: only total_laid_off, percentage_laid_off, funds_raised
SELECT
	COUNT(*) FILTER(WHERE total_laid_off IS NULL) AS total_laid_off_null,
	COUNT(*) FILTER(WHERE percentage_laid_off IS NULL) AS percentage_null,
	COUNT(*) FILTER(WHERE funds_raised IS NULL) AS funds_null,
	COUNT(*) FILTER(WHERE company IS NULL OR location IS NULL OR industry IS NULL
		OR stage IS NULL OR country IS NULL OR "date" IS NULL) AS other_null
FROM layoffs_staging;

-- 8.5 Sanity check on percentages (must be between 0 and 1)
SELECT MIN(percentage_laid_off), MAX(percentage_laid_off) FROM layoffs_staging;
