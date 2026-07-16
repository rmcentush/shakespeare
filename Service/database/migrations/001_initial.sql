CREATE TABLE tenants (
    id uuid PRIMARY KEY,
    external_subject text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE training_events (
    tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    event_id text NOT NULL,
    document_id text NOT NULL,
    event_type text NOT NULL CHECK (event_type IN ('edit_decision', 'document_snapshot')),
    recorded_at timestamptz NOT NULL,
    payload jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    PRIMARY KEY (tenant_id, event_id),
    CHECK (jsonb_typeof(payload) = 'object')
);

CREATE INDEX training_events_tenant_document_idx
    ON training_events (tenant_id, document_id, recorded_at);
CREATE INDEX training_events_expiry_idx ON training_events (expires_at);

CREATE TABLE training_runs (
    id uuid PRIMARY KEY,
    tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    provider text NOT NULL CHECK (provider IN ('tinker')),
    recipe text NOT NULL CHECK (recipe IN ('sft', 'dpo')),
    base_model text NOT NULL,
    config jsonb NOT NULL,
    idempotency_key text NOT NULL,
    request_fingerprint text NOT NULL CHECK (length(request_fingerprint) = 64),
    status text NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued', 'running', 'evaluating', 'succeeded', 'failed', 'cancelled')),
    evaluation_status text NOT NULL DEFAULT 'pending'
        CHECK (evaluation_status IN ('pending', 'passed', 'failed', 'not_applicable')),
    failure_code text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, idempotency_key)
);

CREATE INDEX training_runs_tenant_status_idx ON training_runs (tenant_id, status, created_at);

CREATE TABLE model_versions (
    id uuid PRIMARY KEY,
    tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    training_run_id uuid NOT NULL REFERENCES training_runs(id) ON DELETE CASCADE,
    provider text NOT NULL CHECK (provider IN ('tinker')),
    base_model text NOT NULL,
    sampler_path text NOT NULL,
    state_path text,
    stage text NOT NULL DEFAULT 'candidate'
        CHECK (stage IN ('candidate', 'active', 'retired', 'deletion_pending')),
    evaluation_status text NOT NULL DEFAULT 'pending'
        CHECK (evaluation_status IN ('pending', 'passed', 'failed')),
    dataset_manifest_sha256 text NOT NULL CHECK (length(dataset_manifest_sha256) = 64),
    evaluation_metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
    evaluation_report jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    activated_at timestamptz,
    CHECK (jsonb_typeof(evaluation_metrics) = 'object'),
    CHECK (jsonb_typeof(evaluation_report) = 'object'),
    CHECK (
        evaluation_status <> 'passed' OR (
            evaluation_report ->> 'status' = 'passed'
            AND evaluation_report ->> 'sampler_path' = sampler_path
            AND evaluation_report ->> 'dataset_manifest_sha256' = dataset_manifest_sha256
        )
    )
);

CREATE UNIQUE INDEX model_versions_one_active_per_tenant_idx
    ON model_versions (tenant_id) WHERE stage = 'active';
CREATE INDEX model_versions_tenant_stage_idx ON model_versions (tenant_id, stage, created_at DESC);

CREATE TABLE audit_events (
    id uuid PRIMARY KEY,
    tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    action text NOT NULL,
    resource_type text NOT NULL,
    resource_id text NOT NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX audit_events_tenant_created_idx ON audit_events (tenant_id, created_at DESC);

-- This table contains identifiers and execution state only. Workers claim it across
-- tenants, then set app.tenant_id before reading any tenant-owned content.
CREATE TABLE training_job_queue (
    run_id uuid PRIMARY KEY REFERENCES training_runs(id) ON DELETE CASCADE,
    tenant_id uuid NOT NULL,
    available_at timestamptz NOT NULL DEFAULT now(),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0 AND attempts <= 10),
    lease_owner text,
    lease_expires_at timestamptz,
    last_error_code text
);

CREATE INDEX training_job_queue_claim_idx
    ON training_job_queue (available_at, lease_expires_at, attempts);

-- Checkpoint paths are retained only long enough for a privileged cleanup worker
-- to delete provider-side artifacts after the tenant's service data is purged.
CREATE TABLE checkpoint_deletion_jobs (
    id uuid PRIMARY KEY,
    tenant_fingerprint text NOT NULL CHECK (length(tenant_fingerprint) = 64),
    checkpoint_paths jsonb NOT NULL,
    status text NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued', 'running', 'succeeded', 'failed')),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0 AND attempts <= 10),
    available_at timestamptz NOT NULL DEFAULT now(),
    lease_owner text,
    lease_expires_at timestamptz,
    last_error_code text,
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    CHECK (jsonb_typeof(checkpoint_paths) = 'array')
);

CREATE INDEX checkpoint_deletion_jobs_claim_idx
    ON checkpoint_deletion_jobs (available_at, attempts)
    WHERE status IN ('queued', 'failed');

ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON tenants
    USING (id::text = current_setting('app.tenant_id', true))
    WITH CHECK (id::text = current_setting('app.tenant_id', true));

ALTER TABLE training_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE training_events FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON training_events
    USING (tenant_id::text = current_setting('app.tenant_id', true))
    WITH CHECK (tenant_id::text = current_setting('app.tenant_id', true));

ALTER TABLE training_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE training_runs FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON training_runs
    USING (tenant_id::text = current_setting('app.tenant_id', true))
    WITH CHECK (tenant_id::text = current_setting('app.tenant_id', true));

ALTER TABLE model_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE model_versions FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON model_versions
    USING (tenant_id::text = current_setting('app.tenant_id', true))
    WITH CHECK (tenant_id::text = current_setting('app.tenant_id', true));

ALTER TABLE audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_events FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON audit_events
    USING (tenant_id::text = current_setting('app.tenant_id', true))
    WITH CHECK (tenant_id::text = current_setting('app.tenant_id', true));
