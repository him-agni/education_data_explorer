-- Bronze: CCD school-district (agency) directory, raw as delivered by the Urban Institute.
-- Every source field is kept as a string (primitivesAsString). Nothing is cleaned, renamed or filtered.
-- agency_type tells a regular school division (1) from regional, specialized or state-operated agencies.
-- Lineage: _source_file (the file each row came from) and _ingested_at (load time).
-- Append only. COPY INTO remembers which files it has loaded, so re-running adds zero rows.
-- Run: python scripts/run_sql.py sql/bronze/015_ccd_district_directory.sql --set pulled_on=YYYY-MM-DD

CREATE TABLE IF NOT EXISTS bronze.ccd_district_directory;

COPY INTO bronze.ccd_district_directory
FROM (
  SELECT
    *,
    _metadata.file_path AS _source_file,
    current_timestamp() AS _ingested_at
  FROM '/Volumes/${catalog}/bronze/raw/urban/ccd/district_directory/'
)
FILEFORMAT = JSON
PATTERN = '*/*/part.jsonl'
FORMAT_OPTIONS ('primitivesAsString' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');

COMMENT ON TABLE bronze.ccd_district_directory IS 'Raw, as delivered by Urban Institute (Education Data Portal, CCD school-district directory), pulled on ${pulled_on}. One row per school district or other education agency (leaid) per year as returned by the API. All source fields are strings. Not cleaned. Lineage columns: _source_file, _ingested_at.';
