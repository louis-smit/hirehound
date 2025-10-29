# Job Posting Standards & Schema Research

## Industry Standards

### Schema.org JobPosting

Schema.org's JobPosting is the most widely adopted standard for job posting structured data. It's used by Google for Jobs and other major search engines.

**Key Benefits:**

- Industry-standard vocabulary
- SEO optimization (Google for Jobs rich results)
- Comprehensive property coverage
- Well-documented and maintained

**Core Required Properties:**

- `title` - Job title
- `description` - Full job description (HTML allowed)
- `datePosted` - Publication date (ISO 8601)
- `hiringOrganization` - Company information
- `jobLocation` or `jobLocationType` - Location or remote designation

**Important Recommended Properties:**

- `validThrough` - Application deadline
- `employmentType` - FULL_TIME, PART_TIME, CONTRACTOR, etc.
- `baseSalary` - Salary information
- `identifier` - Unique job ID from source
- `industry` - Industry classification
- `occupationalCategory` - Job category/classification
- `educationRequirements` - Required education level
- `experienceRequirements` - Required experience
- `skills` - Required skills
- `responsibilities` - Job responsibilities

## South African Job Board Analysis

### Common Data Fields Across SA Job Boards

Based on analysis of major SA job boards, most include:

**Essential Fields:**

1. Job Title
2. Company Name
3. Location (City/Province)
4. Job Description
5. Posted Date
6. Job Type (Full-time, Part-time, Contract)
7. Application URL/Method

**Frequently Available:**

1. Salary Range (though often omitted)
2. Required Experience Level
3. Industry/Sector
4. Required Education
5. Required Skills
6. Job Reference Number
7. Closing Date

**Occasionally Available:**

1. Remote Work Options
2. Benefits
3. Company Description
4. Number of positions
5. Security Clearance Requirements
6. Travel Requirements

### Data Quality Variations

**High Quality Sources:**

- PNet: Structured data, comprehensive fields
- LinkedIn: Good standardization, rich metadata
- CareerJunction: Detailed categorization

**Variable Quality Sources:**

- Gumtree: Inconsistent formatting, user-generated
- Smaller job boards: May lack structured data

## Recommended Unified Schema

Our schema should be a superset that can accommodate data from all sources while remaining queryable and efficient.

### Core Principles

1. **Required fields must be obtainable from all sources**
2. **Optional fields capture additional data when available**
3. **Source metadata tracks provenance**
4. **Normalized values enable cross-source querying**
5. **Raw data preserved for reference and re-processing**
6. **Organizations are first-class entities** with their own deduplication and enrichment

### Schema Overview

The system uses three primary entity types:

1. **Organizations** - Companies/employers (deduplicated across sources)
2. **Job Postings** - Individual job postings (linked to organizations)
3. **Duplicate Clusters** - Groups of equivalent entities

## Organization Schema

Organizations are **first-class entities** that exist independently of job postings. We build comprehensive organizational profiles by aggregating data from multiple sources.

**Design Philosophy:** Normalized structure with tables separated by update frequency and cardinality to minimize bloat, maximize query performance, and avoid excessive nullable columns.

### Core Organizations Table
**Purpose:** Minimal, stable identity data that changes infrequently

```
organizations
├── Identity
│   ├── id (UUID, primary key)
│   ├── slug (URL-friendly identifier, unique)
│   ├── name (canonical display name)
│   ├── duplicate_cluster_id (FK to org clusters, nullable)
│   └── is_canonical (boolean, primary org in cluster)
│
├── Core Information
│   ├── description (company overview, text)
│   ├── description_embedding (vector for semantic search)
│   ├── industry_id (FK to industries table)
│   ├── website_url (primary website)
│   ├── logo_url (primary logo URL)
│   ├── logo_file_path (stored locally, nullable)
│   └── quality_score (0-100, based on completeness)
│
├── Metadata
│   ├── created_at (timestamptz)
│   ├── updated_at (timestamptz)
│   ├── raw_data (JSONB, original scraped data)
│   └── processing_notes (JSONB, warnings/issues)
│
└── Search & Matching
    ├── search_vector (tsvector for full-text search)
    ├── name_fingerprint (for fuzzy deduplication)
    └── combined_hash (for exact duplicate detection)
```

### Industries Table
**Purpose:** Controlled vocabulary for industry classification (prevents "IT" vs "Information Technology" chaos)

```
industries
├── id (integer, primary key)
├── name (string, e.g., "Information Technology")
├── slug (string, e.g., "information-technology", unique)
├── parent_id (FK to industries, for hierarchy, nullable)
├── description (text, nullable)
└── industry_code (string, NAICS/SIC code, nullable)
```

### Organization Locations Table
**Purpose:** 1:Many relationship for offices/branches (replaces headquarters_* duplication)

```
organization_locations
├── id (UUID, primary key)
├── organization_id (FK to organizations, indexed)
├── address (string, nullable)
├── city (string, indexed)
├── province (string, indexed)
├── country (ISO 3166-1 alpha-2, default "ZA")
├── coordinates (PostGIS point, nullable)
├── is_headquarters (boolean, default false)
├── is_active (boolean, default true)
├── created_at (timestamptz)
└── updated_at (timestamptz)
```

### Organization Aliases Table
**Purpose:** Track name variations for deduplication matching

```
organization_aliases
├── id (UUID, primary key)
├── organization_id (FK to organizations, indexed)
├── alias_name (string, indexed)
├── alias_type (ENUM: legal, trading, acronym, former, common_misspelling)
├── is_primary (boolean, default false)
├── source (string, where we learned this alias, nullable)
├── verified (boolean, default false)
└── created_at (timestamptz)
```

### Organization Enrichment Table
**Purpose:** Optional data discovered through external APIs/registries (often null initially)

```
organization_enrichment
├── organization_id (FK to organizations, primary key)
├── Legal & Registration
│   ├── legal_name (official registered name, nullable)
│   ├── trading_name (doing-business-as name, nullable)
│   ├── registration_number (company registration, nullable)
│   ├── tax_number (VAT/tax ID, nullable)
│   └── company_type (ENUM: private, public, non_profit, government, nullable)
│
├── Size & Funding
│   ├── size_category (ENUM: startup, small, medium, large, enterprise, nullable)
│   ├── employee_count_min (integer, nullable)
│   ├── employee_count_max (integer, nullable)
│   ├── founded_year (integer, nullable)
│   ├── funding_stage (ENUM: bootstrapped, seed, series_a, series_b, etc., nullable)
│   ├── total_funding_amount (decimal, nullable)
│   └── stock_symbol (string, if publicly traded, nullable)
│
├── External IDs
│   ├── linkedin_id (LinkedIn company ID, nullable)
│   ├── linkedin_url (string, nullable)
│   ├── crunchbase_id (nullable)
│   └── clearbit_id (nullable)
│
└── Metadata
    ├── last_enriched_at (timestamptz, nullable)
    ├── enrichment_status (ENUM: pending, in_progress, complete, failed)
    ├── enrichment_source (string, e.g., "linkedin", "clearbit", nullable)
    └── updated_at (timestamptz)
```

### Organization Social Links Table
**Purpose:** Extensible social media presence (avoids adding columns for each platform)

```
organization_social_links
├── id (UUID, primary key)
├── organization_id (FK to organizations, indexed)
├── platform (ENUM: linkedin, twitter, facebook, instagram, github, youtube, etc.)
├── url (string)
├── username (string, nullable)
├── created_at (timestamptz)
└── updated_at (timestamptz)
```

### Organization Stats Table
**Purpose:** Frequently updated denormalized metrics (separated to avoid bloat on core table)

```
organization_stats
├── organization_id (FK to organizations, primary key)
├── total_active_jobs (integer, default 0)
├── total_all_time_jobs (integer, default 0)
├── avg_job_duration_days (integer, nullable)
├── typical_job_types (JSONB array, nullable)
├── hiring_frequency_score (integer, 0-100, nullable)
├── last_job_posted_at (timestamptz, nullable)
└── updated_at (timestamptz)
```

### Provenance Tracking Table
**Purpose:** Track which sources contributed to organization data (many-to-many)

```
organization_data_sources
├── id (UUID, primary key)
├── organization_id (FK to organizations, indexed)
├── source_name (string, e.g., "pnet", "linkedin", "manual_entry")
├── source_url (string, nullable)
├── data_contributed (JSONB, which fields came from this source)
├── first_seen_at (timestamptz)
├── last_seen_at (timestamptz)
└── is_active (boolean, still contributing data)
```

**Rationale for Normalization:**
- **Reduces NULL columns** - Enrichment data often unavailable initially
- **Prevents table bloat** - Stats update frequently, core data doesn't
- **Improves query performance** - Smaller core table, better index efficiency
- **Enables filtering** - "Find orgs with offices in Cape Town" (can't do with JSONB efficiently)
- **Supports deduplication** - Aliases table critical for fuzzy matching
- **Maintains referential integrity** - Industries controlled vocabulary

### Proposed Field Structure

```
Job Posting (Normalized)
├── Identity
│   ├── id (UUID, primary key)
│   ├── source_id (original job ID from source)
│   ├── source_name (e.g., "pnet", "linkedin")
│   ├── source_url (canonical URL)
│   └── duplicate_cluster_id (for grouped duplicates)
│
├── Core Information
│   ├── title (required, normalized)
│   ├── title_raw (original from source)
│   ├── description (required, sanitized HTML)
│   ├── description_text (plain text extraction)
│   ├── description_embedding (vector for semantic search)
│   └── job_type (ENUM: full_time, part_time, contract, etc.)
│
├── Organization Relationship
│   ├── organization_id (FK to organizations table, REQUIRED)
│   ├── company_name_raw (original from job posting source)
│   ├── department (if specified)
│   ├── posted_by (recruiter name, if available)
│   └── hiring_manager (if specified)
│
├── Location
│   ├── location_type (ENUM: onsite, remote, hybrid)
│   ├── country (ISO 3166-1 alpha-2, default "ZA")
│   ├── province (normalized SA province)
│   ├── city (normalized)
│   ├── location_raw (original text)
│   └── coordinates (PostGIS point, if geocoded)
│
├── Requirements
│   ├── experience_level (ENUM: entry, intermediate, senior, executive)
│   ├── experience_years_min
│   ├── experience_years_max
│   ├── education_level (ENUM: high_school, diploma, bachelors, etc.)
│   ├── required_skills (JSONB array)
│   ├── preferred_skills (JSONB array)
│   └── certifications (JSONB array)
│
├── Compensation
│   ├── salary_min
│   ├── salary_max
│   ├── salary_currency (default "ZAR")
│   ├── salary_period (ENUM: hour, month, year)
│   ├── salary_disclosed (boolean)
│   └── benefits (JSONB array)
│
├── Temporal
│   ├── posted_date (required, timestamptz)
│   ├── closing_date (timestamptz, nullable)
│   ├── first_seen_at (when we first scraped it)
│   ├── last_seen_at (last time we saw it active)
│   └── expires_at (our calculated expiration)
│
├── Metadata
│   ├── scraped_at (when we collected this version)
│   ├── quality_score (0-100, based on completeness)
│   ├── is_active (boolean)
│   ├── is_duplicate (boolean)
│   ├── raw_data (JSONB, original scraped data)
│   └── processing_notes (JSONB, any issues/warnings)
│
└── Search & Matching
    ├── search_vector (tsvector for full-text search)
    ├── title_fingerprint (for fuzzy matching)
    ├── description_fingerprint (MinHash or similar)
    └── combined_hash (for exact duplicate detection)
```

## Data Normalization Strategy

### 1. Company Names

- Strip legal entities (Pty Ltd, Ltd, Inc)
- Handle common variations (ABC Co vs ABC Company)
- Maintain lookup table for known aliases

### 2. Locations

- Map to standard SA provinces
- Normalize city names
- Handle "Multiple Locations" cases
- Support geocoding for mapping features

### 3. Job Titles

- Remove company names from titles
- Standardize common abbreviations
- Map to standard occupational categories

### 4. Skills

- Extract from descriptions using NLP
- Maintain skill taxonomy/ontology
- Normalize variations (JS vs JavaScript)

### 5. Dates

- Convert all to UTC timestamps
- Handle relative dates ("Posted 2 days ago")
- Infer closing dates when missing

## References

- [Schema.org JobPosting](https://schema.org/JobPosting)
- [Google Job Posting Guidelines](https://developers.google.com/search/docs/appearance/structured-data/job-posting)
- [O\*NET Occupational Taxonomy](https://www.onetonline.org/)
