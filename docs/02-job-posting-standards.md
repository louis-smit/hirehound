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

```
Organization
├── Identity
│   ├── id (UUID, primary key)
│   ├── slug (URL-friendly identifier)
│   ├── canonical_name (normalized, official name)
│   ├── name_variations (JSONB array of aliases/variations)
│   ├── duplicate_cluster_id (FK to org clusters)
│   └── is_canonical (boolean, primary org in cluster)
│
├── Core Information
│   ├── legal_name (official registered name)
│   ├── trading_name (doing-business-as name)
│   ├── description (company overview)
│   ├── description_embedding (vector for semantic search)
│   ├── industry (normalized industry category)
│   ├── industry_tags (JSONB array of sub-industries)
│   ├── size_category (ENUM: startup, small, medium, large, enterprise)
│   ├── employee_count_min
│   ├── employee_count_max
│   ├── founded_year
│   └── company_type (ENUM: private, public, non_profit, government)
│
├── Location
│   ├── headquarters_country (ISO 3166-1, default "ZA")
│   ├── headquarters_province
│   ├── headquarters_city
│   ├── headquarters_address
│   ├── headquarters_coordinates (PostGIS point)
│   ├── office_locations (JSONB array of additional offices)
│   └── operates_remotely (boolean)
│
├── Contact & Online Presence
│   ├── website_url (primary website)
│   ├── careers_page_url
│   ├── linkedin_url
│   ├── linkedin_id (LinkedIn company ID)
│   ├── twitter_handle
│   ├── facebook_url
│   ├── contact_email
│   └── phone_number
│
├── Branding
│   ├── logo_url (primary logo)
│   ├── logo_file_path (stored locally)
│   ├── brand_colors (JSONB array of hex colors)
│   └── tagline
│
├── Business Information
│   ├── registration_number (company registration)
│   ├── tax_number (VAT/tax ID)
│   ├── stock_symbol (if publicly traded)
│   ├── funding_stage (ENUM: bootstrapped, seed, series_a, etc.)
│   ├── total_funding_amount
│   ├── revenue_range (ENUM or min/max)
│   └── ownership_structure
│
├── Data Quality & Provenance
│   ├── data_sources (JSONB array: which sources contributed)
│   ├── quality_score (0-100, based on completeness)
│   ├── verified (boolean, manually verified)
│   ├── verification_date
│   ├── last_enriched_at (last external data fetch)
│   └── enrichment_status (ENUM: pending, in_progress, complete, failed)
│
├── Statistics (denormalized)
│   ├── total_active_jobs (current open positions)
│   ├── total_all_time_jobs (historical total)
│   ├── avg_job_duration_days
│   ├── typical_job_types (JSONB array)
│   └── hiring_frequency_score
│
├── Metadata
│   ├── created_at
│   ├── updated_at
│   ├── first_seen_at (first scraped)
│   ├── last_job_posted_at
│   ├── raw_data (JSONB, original scraped data)
│   └── processing_notes (JSONB)
│
└── Search & Matching
    ├── search_vector (tsvector for full-text search)
    ├── name_fingerprint (for fuzzy deduplication)
    └── combined_hash (for exact duplicate detection)
```

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
