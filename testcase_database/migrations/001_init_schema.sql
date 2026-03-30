-- Initial schema for AI-powered Test Case Management System
-- Idempotent: safe to re-run (uses IF NOT EXISTS where possible).

BEGIN;

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Updated-at trigger helper
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ===== Auth & Users =====

CREATE TABLE IF NOT EXISTS roles (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        text NOT NULL UNIQUE,
  description text,
  created_at  timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS users (
  id             uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  email          text NOT NULL UNIQUE,
  password_hash  text NOT NULL,
  display_name   text,
  is_active      boolean NOT NULL DEFAULT true,
  last_login_at  timestamptz,
  created_at     timestamptz NOT NULL DEFAULT NOW(),
  updated_at     timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_roles (
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id    uuid NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, role_id)
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON user_roles(role_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_users_set_updated_at'
  ) THEN
    CREATE TRIGGER trg_users_set_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();
  END IF;
END $$;

-- ===== Projects & Modules =====

CREATE TABLE IF NOT EXISTS projects (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        text NOT NULL,
  description text,
  owner_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  status      text NOT NULL DEFAULT 'active', -- active|archived
  created_at  timestamptz NOT NULL DEFAULT NOW(),
  updated_at  timestamptz NOT NULL DEFAULT NOW(),
  CONSTRAINT projects_name_unique UNIQUE (name)
);

CREATE INDEX IF NOT EXISTS idx_projects_owner ON projects(owner_user_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_projects_set_updated_at'
  ) THEN
    CREATE TRIGGER trg_projects_set_updated_at
    BEFORE UPDATE ON projects
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS modules (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id  uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  name        text NOT NULL,
  description text,
  sort_order  integer NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT NOW(),
  updated_at  timestamptz NOT NULL DEFAULT NOW(),
  CONSTRAINT modules_project_name_unique UNIQUE (project_id, name)
);

CREATE INDEX IF NOT EXISTS idx_modules_project ON modules(project_id);
CREATE INDEX IF NOT EXISTS idx_modules_project_sort ON modules(project_id, sort_order);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_modules_set_updated_at'
  ) THEN
    CREATE TRIGGER trg_modules_set_updated_at
    BEFORE UPDATE ON modules
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();
  END IF;
END $$;

-- ===== Test Cases & Tags =====

CREATE TABLE IF NOT EXISTS tags (
  id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name       text NOT NULL UNIQUE,
  color      text,
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS testcases (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id    uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  module_id     uuid REFERENCES modules(id) ON DELETE SET NULL,
  title         text NOT NULL,
  description   text,
  preconditions text,
  steps         jsonb NOT NULL DEFAULT '[]'::jsonb,     -- [{action, expected}]
  expected      text,
  priority      text NOT NULL DEFAULT 'medium',          -- low|medium|high|critical
  status        text NOT NULL DEFAULT 'active',          -- active|deprecated
  created_by    uuid REFERENCES users(id) ON DELETE SET NULL,
  updated_by    uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT NOW(),
  updated_at    timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_testcases_project ON testcases(project_id);
CREATE INDEX IF NOT EXISTS idx_testcases_module ON testcases(module_id);
CREATE INDEX IF NOT EXISTS idx_testcases_priority ON testcases(priority);
CREATE INDEX IF NOT EXISTS idx_testcases_status ON testcases(status);
CREATE INDEX IF NOT EXISTS idx_testcases_title_trgm ON testcases USING gin (title gin_trgm_ops);

-- trigram support (optional, but improves search); safe if extension missing? pg_trgm is standard.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_testcases_set_updated_at'
  ) THEN
    CREATE TRIGGER trg_testcases_set_updated_at
    BEFORE UPDATE ON testcases
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS testcase_tags (
  testcase_id uuid NOT NULL REFERENCES testcases(id) ON DELETE CASCADE,
  tag_id      uuid NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (testcase_id, tag_id)
);

CREATE INDEX IF NOT EXISTS idx_testcase_tags_tag ON testcase_tags(tag_id);

-- ===== Manual Executions =====

CREATE TABLE IF NOT EXISTS testcase_executions (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id      uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  testcase_id     uuid NOT NULL REFERENCES testcases(id) ON DELETE CASCADE,
  executed_by     uuid REFERENCES users(id) ON DELETE SET NULL,
  status          text NOT NULL,                          -- passed|failed|blocked|skipped
  environment     text,
  notes           text,
  started_at      timestamptz NOT NULL DEFAULT NOW(),
  finished_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_executions_project ON testcase_executions(project_id);
CREATE INDEX IF NOT EXISTS idx_executions_testcase ON testcase_executions(testcase_id);
CREATE INDEX IF NOT EXISTS idx_executions_status ON testcase_executions(status);
CREATE INDEX IF NOT EXISTS idx_executions_started_at ON testcase_executions(started_at);

CREATE TABLE IF NOT EXISTS execution_logs (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  execution_id  uuid NOT NULL REFERENCES testcase_executions(id) ON DELETE CASCADE,
  level         text NOT NULL DEFAULT 'info',              -- info|warn|error|debug
  message       text NOT NULL,
  details       jsonb,
  created_at    timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_execution_logs_execution ON execution_logs(execution_id);
CREATE INDEX IF NOT EXISTS idx_execution_logs_created_at ON execution_logs(created_at);

-- ===== Automation Runs (Playwright) =====

CREATE TABLE IF NOT EXISTS automation_runs (
  id             uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id     uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  module_id      uuid REFERENCES modules(id) ON DELETE SET NULL,
  triggered_by   uuid REFERENCES users(id) ON DELETE SET NULL,
  run_type       text NOT NULL DEFAULT 'playwright',       -- playwright|other
  status         text NOT NULL DEFAULT 'queued',           -- queued|running|passed|failed|canceled
  started_at     timestamptz,
  finished_at    timestamptz,
  summary        text,
  metadata       jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at     timestamptz NOT NULL DEFAULT NOW(),
  updated_at     timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_automation_runs_project ON automation_runs(project_id);
CREATE INDEX IF NOT EXISTS idx_automation_runs_status ON automation_runs(status);
CREATE INDEX IF NOT EXISTS idx_automation_runs_created_at ON automation_runs(created_at);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_automation_runs_set_updated_at'
  ) THEN
    CREATE TRIGGER trg_automation_runs_set_updated_at
    BEFORE UPDATE ON automation_runs
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS automation_run_testcases (
  automation_run_id uuid NOT NULL REFERENCES automation_runs(id) ON DELETE CASCADE,
  testcase_id       uuid NOT NULL REFERENCES testcases(id) ON DELETE CASCADE,
  status            text,                                  -- passed|failed|skipped
  error_message     text,
  duration_ms       integer,
  created_at        timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (automation_run_id, testcase_id)
);

CREATE INDEX IF NOT EXISTS idx_automation_run_testcases_testcase ON automation_run_testcases(testcase_id);

CREATE TABLE IF NOT EXISTS automation_artifacts (
  id               uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  automation_run_id uuid NOT NULL REFERENCES automation_runs(id) ON DELETE CASCADE,
  testcase_id      uuid REFERENCES testcases(id) ON DELETE SET NULL,
  artifact_type    text NOT NULL,                           -- screenshot|video|trace|report|log
  file_name        text NOT NULL,
  content_type     text,
  storage_path     text NOT NULL,                           -- path in local FS or object storage
  size_bytes       bigint,
  metadata         jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at       timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_automation_artifacts_run ON automation_artifacts(automation_run_id);
CREATE INDEX IF NOT EXISTS idx_automation_artifacts_testcase ON automation_artifacts(testcase_id);
CREATE INDEX IF NOT EXISTS idx_automation_artifacts_type ON automation_artifacts(artifact_type);

CREATE TABLE IF NOT EXISTS automation_logs (
  id               uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  automation_run_id uuid NOT NULL REFERENCES automation_runs(id) ON DELETE CASCADE,
  level            text NOT NULL DEFAULT 'info',
  message          text NOT NULL,
  details          jsonb,
  created_at       timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_automation_logs_run ON automation_logs(automation_run_id);
CREATE INDEX IF NOT EXISTS idx_automation_logs_created_at ON automation_logs(created_at);

-- ===== Bugs & Linking =====

CREATE TABLE IF NOT EXISTS bugs (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id    uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  title         text NOT NULL,
  description   text,
  status        text NOT NULL DEFAULT 'open',               -- open|in_progress|resolved|closed
  severity      text NOT NULL DEFAULT 'medium',             -- low|medium|high|critical
  external_url  text,                                      -- link to Jira/GitHub/etc
  created_by    uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT NOW(),
  updated_at    timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_bugs_project ON bugs(project_id);
CREATE INDEX IF NOT EXISTS idx_bugs_status ON bugs(status);
CREATE INDEX IF NOT EXISTS idx_bugs_severity ON bugs(severity);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_bugs_set_updated_at'
  ) THEN
    CREATE TRIGGER trg_bugs_set_updated_at
    BEFORE UPDATE ON bugs
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS bug_links (
  bug_id        uuid NOT NULL REFERENCES bugs(id) ON DELETE CASCADE,
  testcase_id   uuid REFERENCES testcases(id) ON DELETE CASCADE,
  execution_id  uuid REFERENCES testcase_executions(id) ON DELETE SET NULL,
  automation_run_id uuid REFERENCES automation_runs(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (bug_id, testcase_id)
);

CREATE INDEX IF NOT EXISTS idx_bug_links_testcase ON bug_links(testcase_id);
CREATE INDEX IF NOT EXISTS idx_bug_links_execution ON bug_links(execution_id);
CREATE INDEX IF NOT EXISTS idx_bug_links_automation_run ON bug_links(automation_run_id);

-- ===== AI Generations =====

CREATE TABLE IF NOT EXISTS ai_generations (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id    uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  module_id     uuid REFERENCES modules(id) ON DELETE SET NULL,
  requested_by  uuid REFERENCES users(id) ON DELETE SET NULL,
  input_type    text NOT NULL DEFAULT 'user_story',         -- user_story|prompt|other
  input_text    text NOT NULL,
  model         text,
  temperature   numeric,
  tokens_in     integer,
  tokens_out    integer,
  status        text NOT NULL DEFAULT 'completed',          -- queued|running|completed|failed
  error_message text,
  output        jsonb,                                     -- generated test cases payload
  created_at    timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_generations_project ON ai_generations(project_id);
CREATE INDEX IF NOT EXISTS idx_ai_generations_created_at ON ai_generations(created_at);
CREATE INDEX IF NOT EXISTS idx_ai_generations_status ON ai_generations(status);

COMMIT;
