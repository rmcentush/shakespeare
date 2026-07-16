# Database operations

Migrations run as a non-superuser schema owner. The API and workers use separate, least-privilege login roles. Never run the API with a superuser or a role carrying `BYPASSRLS`; either would defeat tenant row-level security.

After creating `shakespeare_api` and `shakespeare_worker` login roles through the platform's secret-management workflow, grant only the following capabilities:

```sql
GRANT CONNECT ON DATABASE shakespeare TO shakespeare_api, shakespeare_worker;
GRANT USAGE ON SCHEMA public TO shakespeare_api, shakespeare_worker;

GRANT SELECT, INSERT, DELETE ON tenants TO shakespeare_api;
GRANT SELECT, INSERT ON training_events TO shakespeare_api;
GRANT SELECT, INSERT ON training_runs TO shakespeare_api;
GRANT SELECT, UPDATE ON model_versions TO shakespeare_api;
GRANT SELECT, INSERT ON audit_events TO shakespeare_api;
GRANT INSERT ON training_job_queue, checkpoint_deletion_jobs TO shakespeare_api;

GRANT SELECT, UPDATE, DELETE ON training_job_queue, checkpoint_deletion_jobs
    TO shakespeare_worker;
GRANT SELECT ON tenants, training_events, training_runs TO shakespeare_worker;
GRANT SELECT, INSERT, UPDATE ON model_versions TO shakespeare_worker;
GRANT INSERT, UPDATE ON audit_events TO shakespeare_worker;
GRANT UPDATE ON training_runs TO shakespeare_worker;
```

Workers claim only the content-free queue tables across tenants. Before reading a run or its training events, a worker opens a transaction and executes `set_config('app.tenant_id', tenant_uuid, true)`. The value is transaction-local and must never be set for a pooled connection outside a transaction.

Backups must be encrypted, continuously tested with point-in-time restore drills, and kept no longer than the published deletion/retention policy. The `training_events_expiry_idx` supports the scheduled retention purge; that job must run under a narrowly scoped maintenance role and report deleted-row counts and failures.
