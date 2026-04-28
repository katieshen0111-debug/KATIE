-- OKR Management System Schema (2026+)

CREATE TABLE roles (
  id BIGSERIAL PRIMARY KEY,
  role_key VARCHAR(50) UNIQUE NOT NULL,
  role_name VARCHAR(100) NOT NULL
);

CREATE TABLE users (
  id BIGSERIAL PRIMARY KEY,
  employee_no VARCHAR(50) UNIQUE NOT NULL,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE departments (
  id BIGSERIAL PRIMARY KEY,
  code VARCHAR(30) UNIQUE NOT NULL,
  name_zh VARCHAR(100) NOT NULL,
  name_en VARCHAR(100),
  parent_department_id BIGINT REFERENCES departments(id)
);

CREATE TABLE sections (
  id BIGSERIAL PRIMARY KEY,
  department_id BIGINT NOT NULL REFERENCES departments(id),
  code VARCHAR(30) UNIQUE NOT NULL,
  name_zh VARCHAR(100) NOT NULL,
  name_en VARCHAR(100)
);

CREATE TABLE org_assignments (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  role_id BIGINT NOT NULL REFERENCES roles(id),
  department_id BIGINT REFERENCES departments(id),
  section_id BIGINT REFERENCES sections(id),
  manager_user_id BIGINT REFERENCES users(id),
  valid_from DATE NOT NULL,
  valid_to DATE,
  CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE okr_cycles (
  id BIGSERIAL PRIMARY KEY,
  cycle_year INT NOT NULL,
  cycle_type VARCHAR(20) NOT NULL DEFAULT 'annual',
  status VARCHAR(20) NOT NULL DEFAULT 'open',
  UNIQUE(cycle_year, cycle_type)
);

CREATE TABLE employee_okr_plans (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  okr_cycle_id BIGINT NOT NULL REFERENCES okr_cycles(id),
  created_by BIGINT NOT NULL REFERENCES users(id),
  copied_from_plan_id BIGINT REFERENCES employee_okr_plans(id),
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, okr_cycle_id)
);

CREATE TABLE objectives (
  id BIGSERIAL PRIMARY KEY,
  plan_id BIGINT NOT NULL REFERENCES employee_okr_plans(id) ON DELETE CASCADE,
  objective_no SMALLINT NOT NULL CHECK (objective_no BETWEEN 1 AND 5),
  title VARCHAR(255) NOT NULL,
  description TEXT,
  function_tag VARCHAR(100) NOT NULL,
  weight NUMERIC(5,2) NOT NULL CHECK (weight >= 0 AND weight <= 100),
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  UNIQUE(plan_id, objective_no)
);

CREATE TABLE key_results (
  id BIGSERIAL PRIMARY KEY,
  objective_id BIGINT NOT NULL REFERENCES objectives(id) ON DELETE CASCADE,
  kr_no SMALLINT NOT NULL,
  metric_name VARCHAR(255) NOT NULL,
  direction VARCHAR(20) NOT NULL CHECK (direction IN ('higher_better', 'lower_better', 'range')),
  baseline_value NUMERIC(12,4),
  target_value NUMERIC(12,4) NOT NULL,
  current_value NUMERIC(12,4) DEFAULT 0,
  unit VARCHAR(30),
  progress_pct NUMERIC(5,2) GENERATED ALWAYS AS (
    CASE
      WHEN direction = 'higher_better' AND target_value > 0 THEN LEAST((current_value / target_value) * 100, 200)
      WHEN direction = 'lower_better' AND current_value > 0 THEN LEAST((target_value / current_value) * 100, 200)
      ELSE NULL
    END
  ) STORED,
  UNIQUE(objective_id, kr_no)
);

CREATE TABLE review_checkpoints (
  id BIGSERIAL PRIMARY KEY,
  okr_cycle_id BIGINT NOT NULL REFERENCES okr_cycles(id),
  checkpoint_type VARCHAR(20) NOT NULL CHECK (checkpoint_type IN ('mid_year', 'end_year')),
  checkpoint_date DATE NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'open',
  UNIQUE(okr_cycle_id, checkpoint_type)
);

CREATE TABLE review_records (
  id BIGSERIAL PRIMARY KEY,
  checkpoint_id BIGINT NOT NULL REFERENCES review_checkpoints(id),
  plan_id BIGINT NOT NULL REFERENCES employee_okr_plans(id),
  self_score_pct NUMERIC(5,2),
  manager_score_pct NUMERIC(5,2),
  employee_comment TEXT,
  manager_comment TEXT,
  reviewed_by BIGINT REFERENCES users(id),
  reviewed_at TIMESTAMP,
  UNIQUE(checkpoint_id, plan_id)
);

CREATE TABLE objective_scores (
  id BIGSERIAL PRIMARY KEY,
  review_record_id BIGINT NOT NULL REFERENCES review_records(id) ON DELETE CASCADE,
  objective_id BIGINT NOT NULL REFERENCES objectives(id),
  score_pct NUMERIC(5,2) NOT NULL,
  weighted_score NUMERIC(6,2) NOT NULL
);

CREATE VIEW v_plan_achievement AS
SELECT
  p.id AS plan_id,
  u.name AS employee_name,
  c.cycle_year,
  ROUND(SUM(os.weighted_score), 2) AS total_achievement_pct
FROM employee_okr_plans p
JOIN users u ON p.user_id = u.id
JOIN okr_cycles c ON p.okr_cycle_id = c.id
JOIN review_records rr ON rr.plan_id = p.id
JOIN objective_scores os ON os.review_record_id = rr.id
GROUP BY p.id, u.name, c.cycle_year;
