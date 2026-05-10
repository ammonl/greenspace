# UN17 Village Rooftop Gardens Architecture

## System Overview

UN17 Village Rooftop Gardens is a bilingual (Danish/English) registration platform that allows UN17 Village residents to register for rooftop planter boxes across two greenhouses. The system serves public users (no authentication) and admin users (email/password authentication).

```mermaid
graph TB
    subgraph Users
        PU[Public Users]
        AU[Admin Users]
    end

    subgraph Frontend
        WEB[Next.js 15 App<br/>React 19 / App Router]
    end

    subgraph Backend
        API[API Server<br/>Node.js / TypeScript]
    end

    subgraph AWS
        SES[SES<br/>Email Delivery]
        RDS[(RDS PostgreSQL 16)]
        SM[Secrets Manager]
    end

    PU --> WEB
    AU --> WEB
    WEB -->|REST API| API
    API --> RDS
    API --> SES
    API --> SM
```

## Frontend Architecture

The frontend is a Next.js 15 application using the App Router with React 19. It uses inline styles and a custom i18n system based on React context.

```mermaid
graph TB
    subgraph "Next.js App Router"
        LAYOUT[layout.tsx<br/>LanguageProvider]
        PAGE[page.tsx<br/>View Router]
    end

    subgraph Views
        PRE[PreOpenPage<br/>Info + countdown]
        LAND[LandingPage<br/>Greenhouse cards]
        MAP[GreenhouseMapPage<br/>Box grid + legend]
    end

    subgraph "Shared Components"
        GC[GreenhouseCard]
        BC[BoxCard]
        BSL[BoxStateLegend]
        GM[GreenhouseMap]
        LS[LanguageSelector]
    end

    subgraph "i18n"
        LP[LanguageProvider<br/>React Context]
        TR[translations.ts<br/>da / en]
    end

    LAYOUT --> PAGE
    PAGE -->|preOpen| PRE
    PAGE -->|open, no selection| LAND
    PAGE -->|greenhouse selected| MAP
    LAND --> GC
    MAP --> GM
    MAP --> BSL
    GM --> BC
    LP --> TR
```

### View Routing

The app uses state-driven view switching (not URL routing):

1. **Pre-open mode** — When current time < opening datetime, show `PreOpenPage`.
2. **Landing** — After opening, show `LandingPage` with greenhouse summary cards.
3. **Map view** — When a greenhouse is selected, show `GreenhouseMapPage` with box grid.

### i18n

Language detection follows this priority:
1. Browser locale (`navigator.language`)
2. Manual user selection via `LanguageSelector`

The `LanguageProvider` React context makes the current language and `t()` translation function available to all components. Translation strings are defined in `translations.ts` with key contracts in `@greenspace/shared`.

## Backend Architecture

The API is a Node.js/TypeScript application using Kysely as a type-safe PostgreSQL query builder.

```mermaid
graph TB
    subgraph "HTTP Layer"
        ROUTER[router.ts<br/>Route Registration]
    end

    subgraph "Routes"
        PUB[public.ts<br/>Status / Boxes / Register / Waitlist]
        AUTH[admin/auth.ts<br/>Login / Change Password]
        ADMIN[admin/*.ts<br/>Registrations / Waitlist / Settings / Admins / Audit]
        HEALTH[health.ts<br/>Health Check]
    end

    subgraph "Middleware"
        AUTHMW[auth.ts<br/>Session Validation]
    end

    subgraph "Libraries"
        PWD[password.ts<br/>Argon2id]
        SESS[session.ts<br/>Token Generation]
        ERR[errors.ts<br/>Typed Errors]
        LOG[logger.ts<br/>Structured Logging]
        AUD[audit.ts<br/>Audit Recording]
        EMAIL[email-service.ts<br/>SES Delivery]
    end

    subgraph "Database Layer"
        CONN[connection.ts<br/>Kysely Pool]
        MIG[migrations/<br/>Schema DDL]
        SEED[seed.ts<br/>Initial Data]
    end

    ROUTER --> PUB
    ROUTER --> AUTH
    ROUTER --> ADMIN
    ROUTER --> HEALTH
    AUTH --> AUTHMW
    ADMIN --> AUTHMW
    AUTH --> PWD
    AUTH --> SESS
    ADMIN --> AUD
    ADMIN --> EMAIL
    PUB --> CONN
    AUTH --> CONN
    ADMIN --> CONN
    CONN --> MIG
    CONN --> SEED
```

### API Surface

| Method | Path                          | Auth   | Description                        |
|--------|-------------------------------|--------|------------------------------------|
| GET    | `/public/status`              | None   | Registration open/closed status    |
| GET    | `/public/greenhouses`         | None   | Greenhouse summary counts          |
| GET    | `/public/boxes`               | None   | Public-safe box states             |
| POST   | `/public/register`            | None   | Register for a planter box         |
| POST   | `/public/waitlist`            | None   | Join waitlist                      |
| POST   | `/admin/auth/login`           | None   | Admin login                        |
| POST   | `/admin/auth/change-password` | Admin  | Change own password                |
| GET    | `/admin/registrations`        | Admin  | List all registrations             |
| POST   | `/admin/registrations`        | Admin  | Create override reservation        |
| POST   | `/admin/registrations/move`   | Admin  | Move registration between boxes    |
| POST   | `/admin/registrations/remove` | Admin  | Remove registration                |
| POST   | `/admin/waitlist/assign`      | Admin  | Assign waitlist entry to box       |
| PATCH  | `/admin/settings/opening-time`| Admin  | Update opening datetime            |
| POST   | `/admin/admins`               | Admin  | Create admin account               |
| DELETE | `/admin/admins/:id`           | Admin  | Delete admin account               |
| GET    | `/admin/audit`                | Admin  | Retrieve audit timeline            |
| GET    | `/health`                     | None   | Health check                       |

## Database Architecture

PostgreSQL 16 with 10 core tables. Schema is managed via Kysely migrations.

```mermaid
erDiagram
    greenhouses ||--o{ planter_boxes : contains
    planter_boxes ||--o| registrations : "occupied by"
    admins ||--|| admin_credentials : "has credentials"
    admins ||--o{ sessions : "has sessions"

    greenhouses {
        uuid id PK
        text name
    }

    planter_boxes {
        int id PK
        text name
        uuid greenhouse_id FK
        text state "available|occupied|reserved"
        text reserved_label
    }

    registrations {
        uuid id PK
        int box_id FK
        text name
        text email
        text apartment_key UK
        text status "active|switched|removed"
    }

    waitlist_entries {
        uuid id PK
        text name
        text email
        text apartment_key
        text status "waiting|assigned|cancelled"
    }

    admins {
        uuid id PK
        text email UK
    }

    admin_credentials {
        uuid admin_id PK,FK
        text password_hash
    }

    sessions {
        uuid id PK
        uuid admin_id FK
        timestamp expires_at
    }

    system_settings {
        uuid id PK
        timestamp opening_datetime
    }

    emails {
        uuid id PK
        text recipient_email
        text status "pending|sent|failed"
        boolean edited_before_send
    }

    audit_events {
        uuid id PK
        timestamp timestamp
        text actor_type "public|admin|system"
        text action
        jsonb before
        jsonb after
    }
```

### Key Constraints

- **One active registration per apartment** — Partial unique index on `apartment_key` where `status = 'active'`.
- **One active occupant per box** — Partial unique index on `box_id` where `status = 'active'`.
- **Immutable audit trail** — Database trigger prevents UPDATE/DELETE on `audit_events`.
- **Box states** — Enum constraint: `available`, `occupied`, `reserved`.
- **FIFO waitlist** — Ordered by `created_at`; duplicate apartment preserves earliest timestamp.

## Infrastructure Architecture

All AWS infrastructure is managed via Terraform with isolated staging and production environments.

```mermaid
graph TB
    subgraph "GitHub"
        REPO[Repository<br/>ammonlarson/greenspace]
        CI[CI Workflow<br/>ci.yml]
        TF_WF[Terraform Workflow<br/>terraform.yml]
    end

    subgraph "AWS (eu-north-1)"
        subgraph "Networking"
            VPC[VPC]
            PUB_SUB[Public Subnets]
            PRIV_SUB[Private Subnets]
            IGW[Internet Gateway]
            NAT[NAT Gateway]
        end

        subgraph "Compute"
            LAMBDA[Lambda<br/>API Function]
            LAMBDA_URL[Function URL]
            EB[EventBridge<br/>Session Cleanup]
            RDS[(RDS PostgreSQL)]
        end

        subgraph "Frontend Hosting"
            AMPLIFY[Amplify<br/>Next.js App]
        end

        subgraph "Email"
            SES_ID[SES Domain Identity]
            SES_DKIM[DKIM Signing]
            SES_CS[Configuration Set]
        end

        subgraph "DNS"
            R53[Route 53<br/>Hosted Zone]
        end

        subgraph "Security"
            IAM_API[API Runtime Role]
            IAM_CI[CI Deploy Role]
            IAM_TF[CI Terraform Role]
            KMS[KMS Encryption Key]
            SECRETS[Secrets Manager]
        end

        subgraph "Monitoring"
            CW[CloudWatch<br/>Log Groups]
            ALARMS[CloudWatch<br/>Alarms]
            DASH[CloudWatch<br/>Dashboard]
            SNS[SNS<br/>Alarm Notifications]
        end

        subgraph "State Backend"
            S3[S3 Bucket<br/>tfstate]
            DDB[DynamoDB<br/>Lock Table]
        end
    end

    REPO --> CI
    REPO --> TF_WF
    TF_WF -->|OIDC| IAM_TF
    IAM_TF --> VPC
    IAM_TF --> LAMBDA
    IAM_TF --> RDS
    IAM_TF --> SES_ID
    IAM_TF --> R53
    IAM_TF --> AMPLIFY
    LAMBDA_URL --> LAMBDA
    EB -->|hourly| LAMBDA
    LAMBDA --> RDS
    LAMBDA --> SES_ID
    LAMBDA --> SECRETS
    VPC --> PUB_SUB
    VPC --> PRIV_SUB
    PUB_SUB --> IGW
    PRIV_SUB --> NAT
    R53 --> SES_ID
    SES_ID --> SES_DKIM
```

### Shared-RDS connectivity

Greenspace is migrating off its dedicated per-environment RDS onto the
shared instance owned by `ammonlarson/infra-shared-db`. Because the
Greenspace VPCs run without NAT (only VPC interface endpoints for SES and
Secrets Manager), Lambda has no internet egress and therefore no public
path to the shared RDS endpoint. The connectivity model is **VPC peering**
between each Greenspace VPC and the shared-db default VPC, with private
DNS resolution enabled on the requester side so the public RDS endpoint
name resolves to a private address inside the peered VPC. See
`docs/adr/0001-shared-rds-connectivity.md` for the full decision record and
`docs/runbooks/shared-rds-migration.md` for the data-migration runbook used
during cutover.

### Environments

| Environment | Domain                | VPC CIDR       | RDS Instance    |
|-------------|----------------------|----------------|-----------------|
| staging     | `staging.un17hub.com`| `10.0.0.0/16`  | `db.t4g.micro`  |
| prod        | `un17hub.com`        | `10.1.0.0/16`  | `db.t4g.micro`  |

### Terraform Module Structure

```
infra/terraform/
├── bootstrap/                 One-time state backend setup
│   ├── main.tf
│   └── variables.tf
├── environments/
│   ├── staging/main.tf        Staging stack configuration
│   └── prod/main.tf           Production stack + subdomain delegation
└── modules/
    └── greenspace_stack/      Shared module for all AWS resources
        ├── main.tf            Naming prefix, provider config
        ├── amplify.tf         Amplify app, branch, and domain association
        ├── api_runtime.tf     Lambda function, Function URL, EventBridge schedule
        ├── database.tf        RDS, Secrets Manager
        ├── dns.tf             Route 53 zone and records
        ├── iam.tf             IAM roles and policies
        ├── monitoring.tf      CloudWatch, KMS, Alarms, Dashboard, SNS
        ├── networking.tf      VPC, subnets, gateways
        ├── outputs.tf         Module outputs
        ├── ses.tf             SES identity, DKIM, config set
        ├── variables.tf       Input variables
        └── iam.tftest.hcl     Least-privilege IAM validation tests
```

### CI/CD Pipeline

```mermaid
graph LR
    PR[Pull Request] -->|trigger| CI_CHECK[CI Check<br/>lint + test + build]
    PR -->|infra changes| TF_FMT[Terraform Format Check]
    PR -->|infra changes| TF_PLAN[Terraform Plan<br/>staging + prod]

    MERGE[Merge to main] -->|trigger| CI_MAIN[CI Check]
    MERGE -->|infra changes| TF_STAGING[Apply Staging]
    TF_STAGING -->|success| TF_PROD[Apply Prod]
```

- **CI** runs on every PR: lint, test, build for all workspaces; `terraform fmt` + `terraform validate`.
- **Terraform** runs when `infra/terraform/**` changes: format check + plan on PRs, apply on merge to main. The `Format Check` job enforces `terraform fmt -check -recursive` and blocks merge when formatting is invalid.
- **Drift detection** runs daily via `drift-detection.yml`; creates a GitHub issue if drift is found.
- **Session cleanup** runs hourly via an EventBridge scheduled rule that invokes the API Lambda. The handler detects the scheduled event and deletes expired sessions (8-hour TTL) from the database.
- **Production apply** runs automatically after staging succeeds.
- **AWS auth** uses GitHub OIDC role assumption (no long-lived keys).

## Shared Package

The `@greenspace/shared` package contains code used by both frontend and backend:

- **Domain constants** — Greenhouse names, 29-box catalog, opening datetime, email config.
- **Types** — Interfaces for all entities (`PlanterBoxPublic`, `Registration`, etc.).
- **Validators** — Address, email, name validation with typed results.
- **DAWA** — Danish Address Web API types and helpers for address autocomplete.
- **i18n contracts** — Translation key definitions and language labels.
- **Enums** — Box states, registration statuses, audit actions.
