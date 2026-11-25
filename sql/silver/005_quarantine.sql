-- Silver quarantine: every bronze row that did not make it into a silver table, with the reason.
-- Nothing is dropped silently. The silver build files add rows with INSERT INTO after this table is reset.
-- Reasons: missing_key, bad_year, bad_id_format, state_mismatch, duplicate_loser, unknown_grade,
--          unexpected_breakdown, bad_enrollment_value, unknown_special_value.
-- Full rebuild: this file empties the table, then each silver build refills its own rows.

CREATE OR REPLACE TABLE silver.quarantine (
  source_table STRING COMMENT 'Bronze table the rejected row came from',
  source_file STRING COMMENT 'Raw file the row was loaded from (bronze _source_file)',
  reason STRING COMMENT 'Why the row was rejected',
  ncessch_raw STRING COMMENT 'School ID exactly as delivered (null for district rows)',
  leaid_raw STRING COMMENT 'District ID exactly as delivered',
  year_raw STRING COMMENT 'Year exactly as delivered',
  grade_raw STRING COMMENT 'Grade exactly as delivered (enrollment rows only)',
  enrollment_raw STRING COMMENT 'Enrollment exactly as delivered (enrollment rows only)',
  row_json STRING COMMENT 'The whole bronze row as JSON, so nothing is lost',
  quarantined_at TIMESTAMP COMMENT 'When the row was quarantined'
)
COMMENT 'Rows rejected during the silver build, with the reason. Rebuilt on every run. bronze rows = silver rows + quarantined rows.';
