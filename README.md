# AWS → Azure Migration Guide (2 SPAs + Express API + MySQL + Documents)

This repository contains the migration backlog and guidance for moving an existing web solution from AWS to Azure.

## Background (Current State)
- **2 Single Page Applications (SPAs)** hosted on AWS (exact service TBD)
- **Express API** website/service exposing HTTP APIs
- **MySQL** database (currently AWS RDS)
- **Documents in S3**, and the Express API likely uses the **AWS S3 SDK** (uploads/downloads/presigned URLs, metadata, lifecycle)
- **Custom domains** currently assigned to:
  - SPA 1
  - SPA 2
  - API
  - S3 bucket (documents)
- Source code currently hosted outside Azure DevOps; you need to **move code to Azure DevOps** and adopt best practices aligned to the **Azure Well-Architected Framework**.

## Target State (Azure)
A typical target architecture for this workload:
- **Azure DevOps**
  - Azure Repos (4 repos: SPA1, SPA2, API, IaC)
  - Pipelines (build + deploy)
  - Branch policies + quality gates
- **Hosting (choose per component)**
  - SPA1: Azure Static Web Apps (recommended for SPAs) *or* Azure App Service
  - SPA2: Azure Static Web Apps *or* Azure App Service
  - Express API: Azure App Service (Node) *or* Azure Container Apps
- **Data & storage**
  - Azure Database for MySQL Flexible Server
  - Azure Storage Account (Blob containers) for documents
- **Edge, DNS, certificates**
  - Azure Front Door (and WAF where required) for global edge + custom domains
  - DNS cutover with reduced TTL + rollback criteria
- **Identity & secrets**
  - Microsoft Entra ID for privileged operations
  - Managed Identity for API → Storage and API → MySQL
  - Azure Key Vault for secrets/certs and Azure DevOps variable groups integration
- **Observability**
  - Application Insights for the API
  - Log Analytics + diagnostic settings for hosting, Storage, MySQL, Front Door/WAF
  - Alerts + action groups + runbooks

## Decisions to Make Early (Unblockers)
These choices affect IaC, networking, DNS, and pipelines.

1. **SPA hosting**: Static Web Apps vs App Service
   - Static Web Apps is usually simpler for SPAs (CDN-like behavior, easy domain config).
   - App Service may be preferred if you need complex runtime behavior at origin.
2. **API hosting**: App Service vs Container Apps
   - App Service is straightforward for Node/Express deployments.
   - Container Apps is attractive if you’re containerizing and want autoscaling patterns.
3. **Networking**: Public endpoints vs Private Endpoints/VNet
   - MySQL + Storage can be public with firewall restrictions, or private via Private Endpoints.
   - Private endpoints add operational complexity (Private DNS zones, name resolution).
4. **Edge & API exposure**: Front Door and/or API Management
   - Front Door for global entry, custom domains, TLS, WAF, routing.
   - API Management for API publishing, throttling, auth patterns, developer portal.
5. **Certificates**: Managed cert vs Key Vault
   - Define renewal/monitoring approach regardless of the option.

## Workstreams (What You Need To Do)
This section turns your backlog into an execution playbook.

### 1) Discovery & Current-State Documentation
Goal: avoid surprises during cutover.
- Document AWS architecture and dependencies (SPAs/API/MySQL/S3/DNS/certs).
- Capture the **4 custom domains**, their DNS records, and certificate source.
- Confirm RDS MySQL version/size/HA/backups/maintenance windows and migration constraints.
- Identify all S3 API usage patterns (uploads/downloads/presigned URLs/metadata/lifecycle).
- Review how documents are referenced in the DB (keys, URLs, paths).

**Deliverables**
- Architecture doc (current and target)
- DNS inventory + cert inventory
- S3 usage matrix + required Azure Blob equivalents

### 2) Azure DevOps Setup & Repository Migration
Goal: establish engineering foundation before production changes.
- Create Azure DevOps organization and project structure.
- Migrate repos preserving history (mirror push recommended):
  - SPA 1 repo
  - SPA 2 repo
  - Express API repo
  - IaC repo
- Implement branch policies:
  - Required reviewers
  - Build validation
  - Required checks/status

**Deliverables**
- Azure DevOps project(s), repo permissions, branch policies

### 3) Landing Zone, Governance, and Security Baseline
Goal: define safe defaults aligned to Well-Architected.
- Define subscriptions/resource groups per environment and ownership model.
- Define naming conventions and mandatory tags (for cost allocation).
- Define least-privilege RBAC roles (devops/app/support).
- Implement Entra ID for privileged operations, and use PIM + MFA + conditional access.
- Define segmentation/perimeter strategy (network identities, roles, resource organization).
- Assign Azure Policy to enforce tagging and baseline diagnostic settings.
- Move secrets to Key Vault; integrate with Azure DevOps variable groups.

**Deliverables**
- Resource organization model + naming/tagging standard
- RBAC matrix
- Policy assignments
- Key Vault + secret rotation approach

### 4) Infrastructure as Code (IaC) & CLI Automation
Goal: make environments repeatable.
- Create/migrate an IaC repo and implement:
  - `az` CLI scripts to provision key services
  - Bicep modules/templates for key services
  - Quality gates for IaC (lint/validate/plan + review)

Recommended modules to keep separate (mirrors your backlog):
- SPA1 hosting
- SPA2 hosting
- Express API hosting
- MySQL
- Storage
- Monitoring
- Front Door

**Deliverables**
- IaC repo with environment parameterization (dev/test/staging/prod)

### 5) Data Migration: RDS MySQL → Azure Database for MySQL
Goal: migrate with validated integrity and clear rollback.
- Create Azure Database for MySQL Flexible Server with sizing/HA/backups.
- Configure firewall/private endpoint/TLS.
- Execute migration (dump/restore, or DMS/replication cutover depending on downtime tolerance).
- Validate data (row counts, checksums where feasible) and application compatibility.
- Update API config to use Azure MySQL endpoint/credentials.
- Use Managed Identity where possible (or use Key Vault-backed secrets if MSI auth is not viable for your driver/runtime).
- Test restore process; document target RPO/RTO.

**Deliverables**
- MySQL server + backups/HA configured
- Migration runbook + validation evidence

### 6) Documents: S3 → Azure Blob Storage (and API refactor)
Goal: move documents and preserve access patterns.
- Create storage account(s) and blob containers.
- Define blob naming/path conventions and metadata mapping from S3 keys.
- Copy documents from S3 to Blob and validate object count/checksums.
- Replace AWS S3 SDK usage in Express API with Azure Blob SDK.
- Implement a SAS token issuance pattern equivalent to S3 presigned URLs.
- Disable public access where possible; use RBAC + scoped SAS.
- Expose blob documents via custom domain (often via Front Door) and update DNS.
- Use managed identity for API to access Blob.

**Deliverables**
- Storage account + containers + lifecycle policies
- Migration verification report (counts/checksums)
- Updated API storage integration + token issuance

### 7) CI/CD Pipelines (Build + Deploy)
Goal: repeatable builds and safe deployments.
- Build pipelines:
  - SPA1: install/test/build artifacts
  - SPA2: install/test/build artifacts
  - API: lint/test/package or container build
- Deploy pipelines:
  - Deploy SPA1 to chosen Azure host
  - Deploy SPA2 to chosen Azure host
  - Deploy API to chosen Azure host with env vars and health checks
- Use environment promotion strategy (dev → test → staging → prod) with approvals and quality gates.
- Configure deployment slots and slot swap strategy for API hosting (where applicable).

**Deliverables**
- Azure DevOps pipelines with environments, approvals, and rollback strategy

### 8) DNS, Custom Domains, TLS and Cutover
Goal: low-risk migration of entrypoints.
- Define DNS cutover plan:
  - TTL reduction schedule
  - monitoring window
  - rollback criteria
- Configure custom domains + HTTPS for:
  - SPA1
  - SPA2
  - API
  - Documents endpoint (Front Door → Blob)
- Define certificate strategy (managed cert vs Key Vault) and renewal monitoring.

**Deliverables**
- DNS cutover runbook + verified domain bindings in Azure

### 9) Observability, Operations, and Reliability
Goal: make the platform supportable.
- Enable Application Insights and structured logging for API.
- Enable diagnostic settings to Log Analytics for App Service/Storage/MySQL/Front Door/WAF.
- Set alerts for availability/latency/errors; define SLO targets.
- Create action groups and attach runbook links for critical alerts.
- Build reliability dashboards (uptime, latency, error budget) for critical flows.
- Implement retry/backoff and circuit breaker patterns for MySQL/Blob dependencies.
- Run baseline load test; validate scaling thresholds and performance SLOs.
- Document common operational tasks and define incident response runbooks.

**Deliverables**
- Dashboards + alerts + runbooks
- Performance baseline report

### 10) Security Hardening (Well-Architected)
Goal: reduce risk and align to best practices.
- WAF policy on Front Door (managed rules + exclusions where needed).
- Enforce HTTPS-only at edge and origins.
- Add rate limiting/headers and consider API gateway patterns.
- Enable Defender for Cloud plans for App Service/Storage/MySQL where appropriate.
- Storage security:
  - Disable shared key/legacy auth where feasible
  - Soft delete/versioning + lifecycle management
- Key Vault protections: RBAC, purge protection, soft delete, diagnostics, secret rotation.
- Threat model the workload and track mitigations in backlog.
- Secure SDLC controls in Azure DevOps (SAST, dependency/secret scanning, provenance).

**Deliverables**
- Security baseline controls enabled + documented exceptions

### 11) Cost Management (FinOps)
Goal: keep costs visible and controlled.
- Create budgets/alerts and enforce tagging.
- Choose LRS/ZRS/GRS for storage and validate RPO/RTO vs cost.
- Build cost model per environment and review daily cost trends.
- Right-size resources and optimize non-prod operating hours.

**Deliverables**
- Budgets + cost dashboards + right-sizing cadence

## Suggested Execution Phases
- **Phase 0 – Discovery**: inventory DNS/certs, confirm MySQL constraints, map S3 usage
- **Phase 1 – DevOps Foundation**: Azure DevOps org, repos, branch policies
- **Phase 2 – IaC + Baseline Platform**: landing zone, security baseline, key services (MySQL/Storage/monitoring)
- **Phase 3 – App Migration**: deploy SPAs + API; refactor API for Blob
- **Phase 4 – Data & Documents Cutover**: migrate MySQL and S3 documents; validate
- **Phase 5 – Edge + Domains Cutover**: Front Door/WAF, custom domains, DNS cutover
- **Phase 6 – Optimize & Validate**: load testing, dashboards, DR drills, cost tuning

## Acceptance Criteria (Definition of Done)
- SPAs and API deployed in Azure with working custom domains and HTTPS
- API uses Azure MySQL and Azure Blob (no AWS SDK usage in prod)
- Documents migrated and validated (counts/checksums)
- Observability in place (logs, metrics, traces, alerts)
- Security baseline applied (WAF, HTTPS-only, RBAC/Key Vault/Policy)
- Operational runbooks exist and restore/DR approach is tested
- Cost controls exist (tags, budgets, review cadence)

## Files
- [`migration-items3.csv`](migration-items3.csv): work items
