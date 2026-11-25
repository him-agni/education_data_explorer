-- Bronze: CCD school enrollment by grade, raw as delivered by the Urban Institute.
-- Every source field is kept as a string (primitivesAsString). Nothing is cleaned, renamed or filtered.
-- The grade 99 rows are the API's "Total" rows: never add them to the individual grades.
-- Lineage: _source_file (the file each row came from) and _ingested_at (load time).
-- Append only. COPY INTO remembers which files it has loaded, so re-running adds zero rows.
-- Run: python scripts/run_sql.py sql/bronze/020_ccd_enrollment.sql --set pulled_on=YYYY-MM-DD

CREATE TABLE IF NOT EXISTS bronze.ccd_enrollment;

COPY INTO bronze.ccd_enrollment
FROM (
  SELECT
    *,
    _metadata.file_path AS _source_file,
    current_timestamp() AS _ingested_at
  FROM '/Volumes/${catalog}/bronze/raw/urban/ccd/enrollment/'
)
FILEFORMAT = JSON
PATTERN = '*/*/part.jsonl'
FORMAT_OPTIONS ('primitivesAsString' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');

COMMENT ON TABLE bronze.ccd_enrollment IS 'Raw, as delivered by Urban Institute (Education Data Portal, CCD school enrollment by grade), pulled on ${pulled_on}. One row per school, grade and year as returned by the API (grade 99 = total). All source fields are strings. Not cleaned. Lineage columns: _source_file, _ingested_at.';
