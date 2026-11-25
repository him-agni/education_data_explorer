-- Bronze: CCD school directory, raw as delivered by the Urban Institute.
-- Every source field is kept as a string (primitivesAsString). Nothing is cleaned, renamed or filtered.
-- Lineage: _source_file (the file each row came from) and _ingested_at (load time).
-- Append only. COPY INTO remembers which files it has loaded, so re-running adds zero rows.
-- Run: python scripts/run_sql.py sql/bronze/010_ccd_directory.sql --set pulled_on=YYYY-MM-DD

CREATE TABLE IF NOT EXISTS bronze.ccd_directory;

COPY INTO bronze.ccd_directory
FROM (
  SELECT
    *,
    _metadata.file_path AS _source_file,
    current_timestamp() AS _ingested_at
  FROM '/Volumes/${catalog}/bronze/raw/urban/ccd/directory/'
)
FILEFORMAT = JSON
PATTERN = '*/*/part.jsonl'
FORMAT_OPTIONS ('primitivesAsString' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');

COMMENT ON TABLE bronze.ccd_directory IS 'Raw, as delivered by Urban Institute (Education Data Portal, CCD school directory), pulled on ${pulled_on}. One row per school per year per state as returned by the API. All source fields are strings. Not cleaned. Lineage columns: _source_file, _ingested_at.';
