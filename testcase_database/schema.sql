-- Convenience entrypoint: run schema (migrations) then seed.
-- Usage (example):
--   psql postgresql://appuser:dbuser123@localhost:5000/myapp -f schema.sql

\i migrations/001_init_schema.sql
\i seed/001_seed_data.sql
