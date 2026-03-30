-- Seed data for AI-powered Test Case Management System
-- Idempotent inserts using ON CONFLICT / WHERE NOT EXISTS.

BEGIN;

-- Roles
INSERT INTO roles (name, description)
VALUES
  ('Admin', 'System administrator with full access'),
  ('QA', 'Quality assurance engineer'),
  ('Developer', 'Developer / engineer')
ON CONFLICT (name) DO UPDATE SET description = EXCLUDED.description;

-- Users (password_hash values are placeholders; backend should replace with bcrypt hashes in real usage)
-- For demo purposes, these are deterministic strings.
INSERT INTO users (email, password_hash, display_name, is_active)
VALUES
  ('admin@example.com', 'demo_hash_admin', 'Admin User', true),
  ('qa@example.com', 'demo_hash_qa', 'QA User', true),
  ('dev@example.com', 'demo_hash_dev', 'Dev User', true)
ON CONFLICT (email) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  is_active = EXCLUDED.is_active;

-- User role assignments
WITH u AS (SELECT id, email FROM users),
     r AS (SELECT id, name FROM roles)
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id
FROM u JOIN r ON (
  (u.email = 'admin@example.com' AND r.name = 'Admin')
  OR (u.email = 'qa@example.com' AND r.name = 'QA')
  OR (u.email = 'dev@example.com' AND r.name = 'Developer')
)
ON CONFLICT (user_id, role_id) DO NOTHING;

-- Project
INSERT INTO projects (name, description, owner_user_id, status)
SELECT
  'Demo Web App',
  'Sample project seeded for local development and UI testing.',
  (SELECT id FROM users WHERE email = 'admin@example.com'),
  'active'
WHERE NOT EXISTS (SELECT 1 FROM projects WHERE name = 'Demo Web App');

-- Modules
INSERT INTO modules (project_id, name, description, sort_order)
SELECT
  p.id,
  m.name,
  m.description,
  m.sort_order
FROM (SELECT id FROM projects WHERE name = 'Demo Web App') p
CROSS JOIN (VALUES
  ('Authentication', 'Login/logout, session management, permissions.', 1),
  ('Checkout', 'Cart, payments, and order confirmation flows.', 2)
) AS m(name, description, sort_order)
ON CONFLICT (project_id, name) DO UPDATE SET
  description = EXCLUDED.description,
  sort_order = EXCLUDED.sort_order;

-- Tags
INSERT INTO tags (name, color)
VALUES
  ('smoke', '#06b6d4'),
  ('regression', '#3b82f6'),
  ('security', '#ef4444'),
  ('payments', '#64748b')
ON CONFLICT (name) DO UPDATE SET color = EXCLUDED.color;

-- Testcases
WITH p AS (SELECT id AS project_id FROM projects WHERE name = 'Demo Web App'),
     auth AS (SELECT id AS module_id FROM modules WHERE name = 'Authentication' AND project_id = (SELECT project_id FROM p)),
     chk AS (SELECT id AS module_id FROM modules WHERE name = 'Checkout' AND project_id = (SELECT project_id FROM p)),
     qa AS (SELECT id AS user_id FROM users WHERE email = 'qa@example.com')
INSERT INTO testcases (
  project_id, module_id, title, description, preconditions, steps, expected, priority, status, created_by, updated_by
)
SELECT
  (SELECT project_id FROM p),
  (SELECT module_id FROM auth),
  'Login with valid credentials',
  'Verify user can login with valid email/password and reach dashboard.',
  'User exists and is active.',
  '[{"action":"Navigate to /login","expected":"Login form is displayed"},{"action":"Enter valid email and password","expected":"Credentials are accepted"},{"action":"Click Sign In","expected":"User is redirected to dashboard"}]'::jsonb,
  'Dashboard is shown and user session is established.',
  'high',
  'active',
  (SELECT user_id FROM qa),
  (SELECT user_id FROM qa)
WHERE NOT EXISTS (
  SELECT 1 FROM testcases WHERE title = 'Login with valid credentials'
);

WITH p AS (SELECT id AS project_id FROM projects WHERE name = 'Demo Web App'),
     chk AS (SELECT id AS module_id FROM modules WHERE name = 'Checkout' AND project_id = (SELECT project_id FROM p)),
     qa AS (SELECT id AS user_id FROM users WHERE email = 'qa@example.com')
INSERT INTO testcases (
  project_id, module_id, title, description, preconditions, steps, expected, priority, status, created_by, updated_by
)
SELECT
  (SELECT project_id FROM p),
  (SELECT module_id FROM chk),
  'Checkout fails with expired card',
  'Verify payment is rejected and user sees an error for expired card.',
  'User has items in cart.',
  '[{"action":"Proceed to checkout","expected":"Payment form displayed"},{"action":"Enter expired card details","expected":"Validation or gateway rejection"},{"action":"Submit payment","expected":"Payment fails and error displayed"}]'::jsonb,
  'Payment is not processed; user sees clear message and can retry.',
  'critical',
  'active',
  (SELECT user_id FROM qa),
  (SELECT user_id FROM qa)
WHERE NOT EXISTS (
  SELECT 1 FROM testcases WHERE title = 'Checkout fails with expired card'
);

-- Testcase tags
WITH tc AS (SELECT id, title FROM testcases),
     t AS (SELECT id, name FROM tags)
INSERT INTO testcase_tags (testcase_id, tag_id)
SELECT tc.id, t.id
FROM tc
JOIN t ON (
  (tc.title = 'Login with valid credentials' AND t.name IN ('smoke', 'regression'))
  OR (tc.title = 'Checkout fails with expired card' AND t.name IN ('payments', 'regression'))
)
ON CONFLICT (testcase_id, tag_id) DO NOTHING;

-- Manual execution + logs (for the expired card test case, failing)
WITH p AS (SELECT id AS project_id FROM projects WHERE name = 'Demo Web App'),
     tc AS (SELECT id AS testcase_id FROM testcases WHERE title = 'Checkout fails with expired card'),
     qa AS (SELECT id AS user_id FROM users WHERE email = 'qa@example.com')
INSERT INTO testcase_executions (project_id, testcase_id, executed_by, status, environment, notes, started_at, finished_at)
SELECT
  (SELECT project_id FROM p),
  (SELECT testcase_id FROM tc),
  (SELECT user_id FROM qa),
  'failed',
  'staging',
  'Payment gateway returned EXPIRED_CARD. Verify message copy.',
  NOW() - interval '2 days',
  NOW() - interval '2 days' + interval '2 minutes'
WHERE NOT EXISTS (
  SELECT 1 FROM testcase_executions e
  WHERE e.testcase_id = (SELECT testcase_id FROM tc)
    AND e.status = 'failed'
);

WITH e AS (
  SELECT id AS execution_id
  FROM testcase_executions
  WHERE status = 'failed'
  ORDER BY created_at DESC
  LIMIT 1
)
INSERT INTO execution_logs (execution_id, level, message, details)
SELECT
  (SELECT execution_id FROM e),
  'error',
  'Payment rejected: EXPIRED_CARD',
  '{"gateway":"mock","code":"EXPIRED_CARD"}'::jsonb
WHERE NOT EXISTS (
  SELECT 1 FROM execution_logs l
  WHERE l.execution_id = (SELECT execution_id FROM e)
    AND l.message = 'Payment rejected: EXPIRED_CARD'
);

-- Automation run + artifacts/logs
WITH p AS (SELECT id AS project_id FROM projects WHERE name = 'Demo Web App'),
     qa AS (SELECT id AS user_id FROM users WHERE email = 'qa@example.com')
INSERT INTO automation_runs (project_id, module_id, triggered_by, run_type, status, started_at, finished_at, summary, metadata)
SELECT
  (SELECT project_id FROM p),
  (SELECT id FROM modules WHERE name = 'Checkout' AND project_id = (SELECT project_id FROM p)),
  (SELECT user_id FROM qa),
  'playwright',
  'failed',
  NOW() - interval '1 day',
  NOW() - interval '1 day' + interval '5 minutes',
  '1 failed, 1 passed',
  '{"branch":"main","commit":"demo","ci":false}'::jsonb
WHERE NOT EXISTS (
  SELECT 1 FROM automation_runs ar
  WHERE ar.summary = '1 failed, 1 passed'
);

WITH ar AS (
  SELECT id AS run_id FROM automation_runs WHERE summary = '1 failed, 1 passed' ORDER BY created_at DESC LIMIT 1
),
tc AS (
  SELECT id AS testcase_id FROM testcases WHERE title = 'Checkout fails with expired card'
)
INSERT INTO automation_run_testcases (automation_run_id, testcase_id, status, error_message, duration_ms)
SELECT
  (SELECT run_id FROM ar),
  (SELECT testcase_id FROM tc),
  'failed',
  'Timeout waiting for payment error banner.',
  123456
ON CONFLICT (automation_run_id, testcase_id) DO UPDATE SET
  status = EXCLUDED.status,
  error_message = EXCLUDED.error_message,
  duration_ms = EXCLUDED.duration_ms;

WITH ar AS (
  SELECT id AS run_id FROM automation_runs WHERE summary = '1 failed, 1 passed' ORDER BY created_at DESC LIMIT 1
),
tc AS (
  SELECT id AS testcase_id FROM testcases WHERE title = 'Checkout fails with expired card'
)
INSERT INTO automation_artifacts (automation_run_id, testcase_id, artifact_type, file_name, content_type, storage_path, size_bytes, metadata)
SELECT
  (SELECT run_id FROM ar),
  (SELECT testcase_id FROM tc),
  'screenshot',
  'failed-checkout.png',
  'image/png',
  'artifacts/demo/failed-checkout.png',
  204800,
  '{"page":"checkout","viewport":"1280x720"}'::jsonb
WHERE NOT EXISTS (
  SELECT 1 FROM automation_artifacts a
  WHERE a.file_name = 'failed-checkout.png'
);

WITH ar AS (
  SELECT id AS run_id FROM automation_runs WHERE summary = '1 failed, 1 passed' ORDER BY created_at DESC LIMIT 1
)
INSERT INTO automation_logs (automation_run_id, level, message, details)
SELECT
  (SELECT run_id FROM ar),
  'error',
  'Test failed: Checkout fails with expired card',
  '{"spec":"checkout.spec.ts","line":42}'::jsonb
WHERE NOT EXISTS (
  SELECT 1 FROM automation_logs l
  WHERE l.message = 'Test failed: Checkout fails with expired card'
);

-- Bug + link to testcase/execution/automation run
WITH p AS (SELECT id AS project_id FROM projects WHERE name = 'Demo Web App'),
     admin_u AS (SELECT id AS user_id FROM users WHERE email = 'admin@example.com')
INSERT INTO bugs (project_id, title, description, status, severity, external_url, created_by)
SELECT
  (SELECT project_id FROM p),
  'Expired card error banner missing',
  'Automation and manual execution indicate missing error banner on checkout for expired card.',
  'open',
  'high',
  NULL,
  (SELECT user_id FROM admin_u)
WHERE NOT EXISTS (
  SELECT 1 FROM bugs b WHERE b.title = 'Expired card error banner missing'
);

WITH b AS (SELECT id AS bug_id FROM bugs WHERE title = 'Expired card error banner missing'),
     tc AS (SELECT id AS testcase_id FROM testcases WHERE title = 'Checkout fails with expired card'),
     e AS (SELECT id AS execution_id FROM testcase_executions WHERE status='failed' ORDER BY created_at DESC LIMIT 1),
     ar AS (SELECT id AS run_id FROM automation_runs WHERE summary = '1 failed, 1 passed' ORDER BY created_at DESC LIMIT 1)
INSERT INTO bug_links (bug_id, testcase_id, execution_id, automation_run_id)
SELECT
  (SELECT bug_id FROM b),
  (SELECT testcase_id FROM tc),
  (SELECT execution_id FROM e),
  (SELECT run_id FROM ar)
ON CONFLICT (bug_id, testcase_id) DO UPDATE SET
  execution_id = EXCLUDED.execution_id,
  automation_run_id = EXCLUDED.automation_run_id;

-- AI generation record
WITH p AS (SELECT id AS project_id FROM projects WHERE name = 'Demo Web App'),
     auth AS (SELECT id AS module_id FROM modules WHERE name = 'Authentication' AND project_id = (SELECT project_id FROM p)),
     qa AS (SELECT id AS user_id FROM users WHERE email = 'qa@example.com')
INSERT INTO ai_generations (project_id, module_id, requested_by, input_type, input_text, model, temperature, tokens_in, tokens_out, status, output)
SELECT
  (SELECT project_id FROM p),
  (SELECT module_id FROM auth),
  (SELECT user_id FROM qa),
  'user_story',
  'As a user, I want to reset my password so that I can regain access.',
  'demo-model',
  0.2,
  120,
  300,
  'completed',
  '{"generated":[{"title":"Password reset request sends email","priority":"high"},{"title":"Reset token expires after TTL","priority":"medium"}]}'::jsonb
WHERE NOT EXISTS (
  SELECT 1 FROM ai_generations g
  WHERE g.input_text LIKE 'As a user, I want to reset my password%'
);

COMMIT;
