# Hirehound - Project Overview

## Vision

Hirehound aims to aggregate job postings from various South African job boards into a unified, searchable database. The system will scrape, normalize, and deduplicate job postings to provide a comprehensive view of the South African job market.

## Core Objectives

1. **Multi-Source Aggregation**: Scrape job postings from major South African job boards
2. **Data Normalization**: Convert diverse job posting formats into a unified schema
3. **Intelligent Deduplication**: Identify and handle duplicate job postings across sources
4. **Extensible Architecture**: Support adding new job boards and data sources over time

## Technology Stack

- **Backend**: Elixir/Phoenix
  - Robust concurrency for scraping operations
  - OTP for reliable background processing
  - Strong pattern matching for data transformation
  
- **Database**: PostgreSQL
  - JSONB support for flexible schema evolution
  - Full-text search capabilities
  - Advanced indexing for deduplication

- **Frontend** (Future): React
  - Modern, responsive UI
  - Real-time updates via Phoenix LiveView or channels

## Target Job Boards (South Africa)

Initial targets for scraping:
- PNet
- CareerJunction
- Gumtree Jobs
- Indeed South Africa
- LinkedIn Jobs (South Africa)
- JobMail
- Jobs.co.za

## Key Challenges

### 1. Duplicate Detection
The same job posting often appears on multiple platforms. We need sophisticated algorithms to:
- Match jobs across different sources
- Handle variations in job titles, descriptions, and company names
- Deal with re-postings and updates

### 2. Data Quality
Different job boards have varying data quality standards. We must:
- Handle missing or incomplete data
- Normalize inconsistent formats
- Validate and enrich data where possible

### 3. Scraping Complexity
Each job board has unique:
- HTML structure and CSS selectors
- Rate limiting and anti-scraping measures
- Data update frequencies

### 4. Scalability
As we add more sources and accumulate historical data:
- Database size will grow significantly
- Deduplication complexity increases
- Query performance must remain fast

## Success Metrics

- **Coverage**: Percentage of available jobs captured
- **Freshness**: Time lag between job posting and ingestion
- **Accuracy**: Duplicate detection precision and recall
- **Performance**: Query response times and scraping throughput
