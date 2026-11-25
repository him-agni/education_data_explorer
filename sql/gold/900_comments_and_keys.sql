-- Gold documentation layer: a plain-English comment on every column, then informational primary and foreign keys.
-- Genie reads these comments, so each says what the value is, its unit, and the words people use for it.
-- Year meaning (Urban Institute codebook): school_year is the year the school year BEGINS, so 2023 means the
-- 2023-24 school year (fall membership counted in fall 2023). school_year_label shows it as text.
-- Informational keys are not enforced by Databricks. They document how tables join.
-- Run after the 010 to 060 gold files.

-- ===== gold.state_year_enrollment =====
COMMENT ON COLUMN gold.state_year_enrollment.state_fips IS 'Federal FIPS code of the state (Virginia = 51). Join key.';
COMMENT ON COLUMN gold.state_year_enrollment.state_name IS 'State name, for example Virginia.';
COMMENT ON COLUMN gold.state_year_enrollment.school_year IS 'Year the school year begins as a number: 2023 means the 2023-24 school year. Fall membership is counted in the fall of this year. Also called year or academic year.';
COMMENT ON COLUMN gold.state_year_enrollment.school_year_label IS 'The school year as text, for example 2023-24.';
COMMENT ON COLUMN gold.state_year_enrollment.total_enrollment IS 'Total public school students in the state in that school year, all grades (pre-kindergarten to grade 12 and ungraded), all agencies. Fall membership headcount. Also called enrollment, students, statewide enrollment.';
COMMENT ON COLUMN gold.state_year_enrollment.schools_reporting IS 'Number of schools that reported an enrollment total that year. It varies from year to year while the student total stays steady.';
COMMENT ON COLUMN gold.state_year_enrollment.kindergarten_enrollment IS 'Number of kindergarten students in the state that year (grade level kindergarten only, not pre-kindergarten).';
COMMENT ON COLUMN gold.state_year_enrollment.prior_year_enrollment IS 'total_enrollment of the previous school year. Empty for the first year.';
COMMENT ON COLUMN gold.state_year_enrollment.change_from_prior_year IS 'Change in students from the previous school year (headcount). Negative means decline.';
COMMENT ON COLUMN gold.state_year_enrollment.pct_change_from_prior_year IS 'Percent change in students from the previous school year, for example 1.26 means +1.26 percent. Use this when asked about growth or decline unless a headcount is requested.';

-- ===== gold.division_year_enrollment =====
COMMENT ON COLUMN gold.division_year_enrollment.leaid IS 'Federal 7-digit identifier of the school division (also called district or LEA). Stable across years even when the name changes. Join key.';
COMMENT ON COLUMN gold.division_year_enrollment.division_name IS 'Official name of the school division, for example Fairfax County Public Schools. Latest name, used for every year. Also called district, school district, school system, LEA, or school division. Match people''s short names such as Fairfax with LIKE.';
COMMENT ON COLUMN gold.division_year_enrollment.division_type IS 'County, City or Other, taken from the name (Other: Alleghany Highlands, Colonial Beach, West Point). Richmond City and Richmond County are different divisions.';
COMMENT ON COLUMN gold.division_year_enrollment.county_name IS 'County or independent city the division is located in, as listed in the federal directory, for example Fairfax County or Alexandria city.';
COMMENT ON COLUMN gold.division_year_enrollment.state_fips IS 'Federal FIPS code of the state (Virginia = 51).';
COMMENT ON COLUMN gold.division_year_enrollment.state_name IS 'State name, for example Virginia.';
COMMENT ON COLUMN gold.division_year_enrollment.school_year IS 'Year the school year begins as a number: 2023 means the 2023-24 school year. Fall membership counted in the fall of this year. Also called year.';
COMMENT ON COLUMN gold.division_year_enrollment.school_year_label IS 'The school year as text, for example 2023-24.';
COMMENT ON COLUMN gold.division_year_enrollment.total_enrollment IS 'Total public school students in the division that school year, all grades. Fall membership headcount. Also called enrollment, students, headcount. Schools with no reported total are left out of the sum.';
COMMENT ON COLUMN gold.division_year_enrollment.schools_reporting IS 'Number of the division''s schools that reported an enrollment total that year.';
COMMENT ON COLUMN gold.division_year_enrollment.schools_missing_enrollment IS 'Number of the division''s schools with no reported enrollment total that year (their students are not in total_enrollment).';
COMMENT ON COLUMN gold.division_year_enrollment.prior_year_enrollment IS 'total_enrollment of the previous school year for the same division. Empty when there is no previous year.';
COMMENT ON COLUMN gold.division_year_enrollment.change_from_prior_year IS 'Change in students from the previous school year (headcount). Negative means decline. Use for growth in numbers of students.';
COMMENT ON COLUMN gold.division_year_enrollment.pct_change_from_prior_year IS 'Percent change in students from the previous school year, for example 3.5 means +3.5 percent. Use this for growth or shrinkage unless a headcount is requested. For change over several years, compare total_enrollment of the two years.';
COMMENT ON COLUMN gold.division_year_enrollment.large_swing_flag IS 'True when the division''s enrollment changed by 15 percent or more in one year. Such a change can come from a merger or a reporting change (for example Covington City merged into Alleghany Highlands in 2022), not only real growth or decline. The cause is not recorded here.';

-- ===== gold.school_year_profile =====
COMMENT ON COLUMN gold.school_year_profile.ncessch IS 'Federal 12-digit school identifier. A school that changes school division gets a new identifier. Join key.';
COMMENT ON COLUMN gold.school_year_profile.school_name IS 'School name as listed in that school year.';
COMMENT ON COLUMN gold.school_year_profile.leaid IS 'Federal 7-digit identifier of the school''s division or agency in that year.';
COMMENT ON COLUMN gold.school_year_profile.division_name IS 'Latest name of the school''s division or agency, for example Fairfax County Public Schools. Also called district or school system.';
COMMENT ON COLUMN gold.school_year_profile.is_regular_school_division IS 'True when the school belongs to a regular school division. False for regional programs, specialized schools and state-operated agencies (for example technical centers, Governor''s Schools, hospital schools).';
COMMENT ON COLUMN gold.school_year_profile.state_fips IS 'Federal FIPS code of the state (Virginia = 51).';
COMMENT ON COLUMN gold.school_year_profile.state_name IS 'State name.';
COMMENT ON COLUMN gold.school_year_profile.school_year IS 'Year the school year begins as a number: 2023 means the 2023-24 school year. Also called year.';
COMMENT ON COLUMN gold.school_year_profile.school_year_label IS 'The school year as text, for example 2023-24.';
COMMENT ON COLUMN gold.school_year_profile.school_status IS 'Status of the school at the start of the school year: Open, New, Closed, Reopened, Changed agency, Future (not yet open), and others. Filter to Open, New or Reopened to count operating schools.';
COMMENT ON COLUMN gold.school_year_profile.school_level IS 'School level: Primary, Middle, High, Secondary, Prekindergarten, Other, Not applicable, Missing/not reported.';
COMMENT ON COLUMN gold.school_year_profile.school_type IS 'School type: Regular school, Special education school, Vocational school, Other/alternative school, Reportable program.';
COMMENT ON COLUMN gold.school_year_profile.locale IS 'Degree of urbanization of the school location, for example City, large; Suburb, midsize; Town, remote; Rural, distant. Also called locale or urban-rural category.';
COMMENT ON COLUMN gold.school_year_profile.is_charter IS 'True when the school is a charter school. Virginia has very few (7 to 8 schools in any year).';
COMMENT ON COLUMN gold.school_year_profile.virtual_status IS 'Whether the school is virtual: No, Yes, Virtual with face to face options, Supplemental virtual.';
COMMENT ON COLUMN gold.school_year_profile.title_i_status IS 'Title I status in words. Only filled for school years 2015 to 2021; empty for 2022 to 2024 because the source gives no values.';
COMMENT ON COLUMN gold.school_year_profile.is_title_i_eligible IS 'True when the school is eligible for Title I (targeted assistance or schoolwide), false when it is not. Only filled for school years 2015 to 2021.';
COMMENT ON COLUMN gold.school_year_profile.lowest_grade_offered IS 'Lowest grade the school offers, for example Pre-K, Kindergarten, Grade 6.';
COMMENT ON COLUMN gold.school_year_profile.highest_grade_offered IS 'Highest grade the school offers, for example Grade 5 or Grade 12.';
COMMENT ON COLUMN gold.school_year_profile.total_enrollment IS 'Total students in the school that school year, all grades. Fall membership headcount. Empty when the school did not report.';
COMMENT ON COLUMN gold.school_year_profile.enrollment_status IS 'reported when total_enrollment has a value, missing when the school did not report one.';

-- ===== gold.division_year_grade =====
COMMENT ON COLUMN gold.division_year_grade.leaid IS 'Federal 7-digit identifier of the school division. Join key.';
COMMENT ON COLUMN gold.division_year_grade.division_name IS 'Official name of the school division (latest name). Also called district or school system.';
COMMENT ON COLUMN gold.division_year_grade.school_year IS 'Year the school year begins as a number: 2023 means the 2023-24 school year. Also called year.';
COMMENT ON COLUMN gold.division_year_grade.school_year_label IS 'The school year as text, for example 2023-24.';
COMMENT ON COLUMN gold.division_year_grade.grade_code IS 'Grade as a number for sorting: -1 pre-kindergarten, 0 kindergarten, 1 to 12 for grades 1 to 12.';
COMMENT ON COLUMN gold.division_year_grade.grade IS 'Grade in words: Pre-K, Kindergarten, Grade 1 to Grade 12.';
COMMENT ON COLUMN gold.division_year_grade.enrollment IS 'Students in that grade in the division that school year. Fall membership headcount. The rows of one division and year add up to the division total.';
COMMENT ON COLUMN gold.division_year_grade.schools_with_grade IS 'Number of the division''s schools that reported students in that grade.';
COMMENT ON COLUMN gold.division_year_grade.prior_year_enrollment IS 'Students in the same grade and division the previous school year.';
COMMENT ON COLUMN gold.division_year_grade.change_from_prior_year IS 'Change in students in that grade from the previous school year (headcount).';
COMMENT ON COLUMN gold.division_year_grade.pct_change_from_prior_year IS 'Percent change in students in that grade from the previous school year.';

-- ===== gold.school_openings_closings =====
COMMENT ON COLUMN gold.school_openings_closings.ncessch IS 'Federal 12-digit school identifier. A school that changes division gets a new identifier (see changed_agency).';
COMMENT ON COLUMN gold.school_openings_closings.school_name IS 'Latest school name.';
COMMENT ON COLUMN gold.school_openings_closings.leaid IS 'Identifier of the school''s division in its last listed year.';
COMMENT ON COLUMN gold.school_openings_closings.division_name IS 'Latest name of the school''s division. Also called district.';
COMMENT ON COLUMN gold.school_openings_closings.state_fips IS 'Federal FIPS code of the state (Virginia = 51).';
COMMENT ON COLUMN gold.school_openings_closings.state_name IS 'State name.';
COMMENT ON COLUMN gold.school_openings_closings.first_school_year_listed IS 'First school year (beginning year, 2023 = 2023-24) the school appears in the data, which starts in 2015. Not the opening year: schools can be listed as Future before they open.';
COMMENT ON COLUMN gold.school_openings_closings.last_school_year_listed IS 'Last school year (beginning year) the school appears in the data.';
COMMENT ON COLUMN gold.school_openings_closings.years_listed IS 'Number of school years the school appears in the data.';
COMMENT ON COLUMN gold.school_openings_closings.first_status IS 'Status in the first listed year.';
COMMENT ON COLUMN gold.school_openings_closings.last_status IS 'Status in the last listed year: Open, New, Closed, Reopened, Changed agency, Future.';
COMMENT ON COLUMN gold.school_openings_closings.opened_school_year IS 'School year (beginning year) the school opened: the first year its status is New. Empty for schools already open when the data starts in 2015. To count schools opened per year, group by this column.';
COMMENT ON COLUMN gold.school_openings_closings.reopened_school_year IS 'School year (beginning year) the school reopened after closing, when its status is Reopened.';
COMMENT ON COLUMN gold.school_openings_closings.closed_school_year IS 'School year (beginning year) of a permanent closing: the last listed year, only when the last status is Closed. To count schools closed per year, group by this column. Schools that changed division are not closings.';
COMMENT ON COLUMN gold.school_openings_closings.had_temporary_closed_status IS 'True when the school shows Closed in some year but appears again later, so it did not permanently close.';
COMMENT ON COLUMN gold.school_openings_closings.changed_agency IS 'True when the school moved to another division and got a new identifier. This is not an opening or a closing.';
COMMENT ON COLUMN gold.school_openings_closings.is_open_in_latest_year IS 'True when the school is listed in the latest school year with status Open, New or Reopened.';

-- ===== gold.division_year_demographics =====
COMMENT ON COLUMN gold.division_year_demographics.leaid IS 'Federal 7-digit identifier of the school division. Join key.';
COMMENT ON COLUMN gold.division_year_demographics.division_name IS 'Official name of the school division (latest name). Also called district or school system.';
COMMENT ON COLUMN gold.division_year_demographics.school_year IS 'Year the school year begins as a number: 2023 means the 2023-24 school year. Also called year.';
COMMENT ON COLUMN gold.division_year_demographics.school_year_label IS 'The school year as text, for example 2023-24.';
COMMENT ON COLUMN gold.division_year_demographics.race_code IS 'Race group as a number: 1 White, 2 Black, 3 Hispanic, 4 Asian, 5 American Indian or Alaska Native, 6 Native Hawaiian or other Pacific Islander, 7 Two or more races, 9 Unknown.';
COMMENT ON COLUMN gold.division_year_demographics.race IS 'Race and ethnicity group in words. Also called race, ethnicity, demographic group. Unknown exists for only some schools.';
COMMENT ON COLUMN gold.division_year_demographics.enrollment IS 'Students in that race group in the division that school year (all grades, fall membership headcount). The groups of one division and year add up to the division total.';
COMMENT ON COLUMN gold.division_year_demographics.schools_reporting IS 'Number of the division''s schools that reported students for this group.';
COMMENT ON COLUMN gold.division_year_demographics.pct_of_division_enrollment IS 'This group''s share of the division''s students that year, as a percent from 0 to 100 (for example 12.5 means 12.5 percent). Also called demographic mix, share, composition. The shares of one division and year add up to 100.';

-- ===== informational primary keys (columns must be NOT NULL first) =====
ALTER TABLE gold.state_year_enrollment ALTER COLUMN state_fips SET NOT NULL;
ALTER TABLE gold.state_year_enrollment ALTER COLUMN school_year SET NOT NULL;
ALTER TABLE gold.state_year_enrollment ADD CONSTRAINT pk_state_year_enrollment PRIMARY KEY (state_fips, school_year);

ALTER TABLE gold.division_year_enrollment ALTER COLUMN leaid SET NOT NULL;
ALTER TABLE gold.division_year_enrollment ALTER COLUMN school_year SET NOT NULL;
ALTER TABLE gold.division_year_enrollment ALTER COLUMN state_fips SET NOT NULL;
ALTER TABLE gold.division_year_enrollment ADD CONSTRAINT pk_division_year_enrollment PRIMARY KEY (leaid, school_year);

ALTER TABLE gold.school_year_profile ALTER COLUMN ncessch SET NOT NULL;
ALTER TABLE gold.school_year_profile ALTER COLUMN school_year SET NOT NULL;
ALTER TABLE gold.school_year_profile ADD CONSTRAINT pk_school_year_profile PRIMARY KEY (ncessch, school_year);

ALTER TABLE gold.division_year_grade ALTER COLUMN leaid SET NOT NULL;
ALTER TABLE gold.division_year_grade ALTER COLUMN school_year SET NOT NULL;
ALTER TABLE gold.division_year_grade ALTER COLUMN grade_code SET NOT NULL;
ALTER TABLE gold.division_year_grade ADD CONSTRAINT pk_division_year_grade PRIMARY KEY (leaid, school_year, grade_code);

ALTER TABLE gold.school_openings_closings ALTER COLUMN ncessch SET NOT NULL;
ALTER TABLE gold.school_openings_closings ADD CONSTRAINT pk_school_openings_closings PRIMARY KEY (ncessch);

ALTER TABLE gold.division_year_demographics ALTER COLUMN leaid SET NOT NULL;
ALTER TABLE gold.division_year_demographics ALTER COLUMN school_year SET NOT NULL;
ALTER TABLE gold.division_year_demographics ALTER COLUMN race_code SET NOT NULL;
ALTER TABLE gold.division_year_demographics ADD CONSTRAINT pk_division_year_demographics PRIMARY KEY (leaid, school_year, race_code);

-- ===== informational foreign keys =====
ALTER TABLE gold.division_year_enrollment ADD CONSTRAINT fk_division_year_state
  FOREIGN KEY (state_fips, school_year) REFERENCES gold.state_year_enrollment (state_fips, school_year);
ALTER TABLE gold.division_year_grade ADD CONSTRAINT fk_division_year_grade_division
  FOREIGN KEY (leaid, school_year) REFERENCES gold.division_year_enrollment (leaid, school_year);
ALTER TABLE gold.division_year_demographics ADD CONSTRAINT fk_division_year_demographics_division
  FOREIGN KEY (leaid, school_year) REFERENCES gold.division_year_enrollment (leaid, school_year);
