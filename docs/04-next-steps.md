# Next Steps & Implementation Roadmap

## Phase 1: Foundation (Weeks 1-2)

### 1.1 Database Schema Design
**Goal:** Finalize and implement the normalized job posting schema

**Tasks:**
- [ ] Review and refine schema from `02-job-listing-standards.md`
- [ ] Create Phoenix migration files
- [ ] Design indexes for query performance
- [ ] Set up PostGIS extension for location features
- [ ] Create seed data for testing

**Deliverables:**
- Ecto schemas and migrations
- Database documentation
- Sample seed data (50-100 test jobs)

### 1.2 Data Model Implementation
**Goal:** Build Elixir modules for job data management

**Tasks:**
- [ ] Create Ecto schemas for:
  - `JobPosting`
  - `Company`
  - `DuplicateCluster`
  - `DuplicateRelationship`
  - `ScrapingLog`
- [ ] Implement changesets with validation
- [ ] Add query helpers and scopes
- [ ] Write unit tests

**Deliverables:**
- `lib/hirehound/jobs/` module
- Comprehensive test coverage

### 1.3 Normalization Pipeline
**Goal:** Build data normalization and cleaning utilities

**Tasks:**
- [ ] Company name normalization module
- [ ] Location normalization (SA provinces/cities)
- [ ] Job title standardization
- [ ] Date parsing utilities
- [ ] HTML sanitization for descriptions
- [ ] Skill extraction (basic keyword matching)

**Deliverables:**
- `lib/hirehound/normalization/` module
- Lookup tables for common variations
- Documentation of normalization rules

## Phase 2: Scraping Infrastructure (Weeks 3-4)

### 2.1 Scraper Framework
**Goal:** Build reusable scraping infrastructure

**Tasks:**
- [ ] Create base scraper behaviour/module
- [ ] Implement rate limiting
- [ ] Add retry logic with exponential backoff
- [ ] Set up user agent rotation
- [ ] Error handling and logging
- [ ] Add scraping job queue (Oban)

**Deliverables:**
- `lib/hirehound/scrapers/base_scraper.ex`
- Configurable scraping pipeline
- Queue dashboard for monitoring

### 2.2 First Scraper Implementation
**Goal:** Build scraper for one job board (e.g., PNet)

**Tasks:**
- [ ] Analyze PNet HTML structure
- [ ] Build CSS selectors/parsing logic
- [ ] Map PNet fields to our schema
- [ ] Handle pagination
- [ ] Test with real data
- [ ] Document scraping approach

**Deliverables:**
- `lib/hirehound/scrapers/pnet_scraper.ex`
- Scraping documentation
- Sample scraped data

### 2.3 Scraper Scheduler
**Goal:** Automate periodic scraping

**Tasks:**
- [ ] Set up Oban cron jobs
- [ ] Configure scraping frequency per source
- [ ] Add health checks
- [ ] Implement failure notifications
- [ ] Create scraping metrics dashboard

**Deliverables:**
- Automated scraping pipeline
- Monitoring dashboard
- Alert configuration

## Phase 3: Deduplication System (Weeks 5-6)

### 3.1 Exact & Near Duplicate Detection
**Goal:** Implement first two stages of deduplication

**Tasks:**
- [ ] Hash-based exact duplicate detection
- [ ] MinHash/LSH for near duplicates
- [ ] Create deduplication indexes
- [ ] Build candidate generation system (blocking)
- [ ] Test with real scraped data

**Deliverables:**
- `lib/hirehound/deduplication/exact_matcher.ex`
- `lib/hirehound/deduplication/near_matcher.ex`
- Performance benchmarks

### 3.2 Fuzzy Matching Pipeline
**Goal:** Implement multi-signal fuzzy duplicate detection

**Tasks:**
- [ ] Title similarity scoring
- [ ] Company matching with aliases
- [ ] Location matching logic
- [ ] Description similarity (TF-IDF)
- [ ] Temporal proximity scoring
- [ ] Weighted score combination
- [ ] Threshold tuning

**Deliverables:**
- `lib/hirehound/deduplication/fuzzy_matcher.ex`
- Configuration for threshold tuning
- Accuracy metrics on test data

### 3.3 Clustering Implementation
**Goal:** Group duplicates into clusters

**Tasks:**
- [ ] Connected components algorithm
- [ ] Canonical selection logic
- [ ] Cluster update mechanism
- [ ] Handle edge cases (repostings, multiple positions)
- [ ] Build admin review interface

**Deliverables:**
- `lib/hirehound/deduplication/clustering.ex`
- Admin UI for cluster management
- Cluster quality metrics

## Phase 4: API & Basic UI (Weeks 7-8)

### 4.1 REST API
**Goal:** Expose job data via API

**Tasks:**
- [ ] Design API endpoints
  - GET /api/jobs (search/filter)
  - GET /api/jobs/:id
  - GET /api/companies
  - GET /api/stats
- [ ] Implement pagination
- [ ] Add filtering and sorting
- [ ] Rate limiting
- [ ] API documentation (OpenAPI/Swagger)

**Deliverables:**
- RESTful API
- API documentation
- Example client code

### 4.2 Search Functionality
**Goal:** Enable full-text and faceted search

**Tasks:**
- [ ] Full-text search with PostgreSQL tsvector
- [ ] Faceted filtering (location, company, job type)
- [ ] Search result ranking
- [ ] Search suggestions/autocomplete
- [ ] Save searches feature

**Deliverables:**
- `lib/hirehound/search/` module
- Search API endpoints
- Search performance optimization

### 4.3 Admin Dashboard
**Goal:** Build internal tools for monitoring

**Tasks:**
- [ ] Phoenix LiveView dashboard
- [ ] Scraping status and logs
- [ ] Deduplication metrics
- [ ] Manual duplicate review queue
- [ ] Company alias management
- [ ] Data quality reports

**Deliverables:**
- `/admin` routes and LiveViews
- Real-time monitoring
- Admin documentation

## Phase 5: Enhancement & Scale (Weeks 9-12)

### 5.1 Additional Scrapers
**Goal:** Add more job board sources

**Tasks:**
- [ ] CareerJunction scraper
- [ ] LinkedIn scraper (consider API vs scraping)
- [ ] Indeed South Africa scraper
- [ ] Gumtree Jobs scraper
- [ ] JobMail scraper

**Deliverables:**
- 5+ active scrapers
- Multi-source data in database

### 5.2 Advanced Features
**Goal:** Improve data quality and insights

**Tasks:**
- [ ] Skill taxonomy and tagging
- [ ] Salary estimation for undisclosed postings
- [ ] Company enrichment (size, industry, description)
- [ ] Geocoding for all locations
- [ ] Job trend analytics
- [ ] Email alerts for new jobs

**Deliverables:**
- Enhanced job data
- Analytics features
- User notification system

### 5.3 Performance Optimization
**Goal:** Ensure system scales efficiently

**Tasks:**
- [ ] Database query optimization
- [ ] Caching strategy (Redis/ETS)
- [ ] Background job prioritization
- [ ] CDN setup for static assets
- [ ] Database partitioning for old data
- [ ] Load testing

**Deliverables:**
- Performance benchmarks
- Caching implementation
- Scalability documentation

## Phase 6: Public Launch Prep (Weeks 13+)

### 6.1 React Frontend
**Goal:** Build user-facing job search interface

**Tasks:**
- [ ] Design mockups/wireframes
- [ ] Set up React + TypeScript
- [ ] Build component library
- [ ] Implement search interface
- [ ] Job detail views
- [ ] Company pages
- [ ] User accounts (save jobs, alerts)

**Deliverables:**
- Production-ready frontend
- Mobile-responsive design

### 6.2 Legal & Compliance
**Goal:** Ensure legal compliance

**Tasks:**
- [ ] Review scraping legality (robots.txt, ToS)
- [ ] POPIA compliance (SA data protection)
- [ ] Privacy policy
- [ ] Terms of service
- [ ] Attribution requirements
- [ ] Data retention policy

**Deliverables:**
- Legal documentation
- Compliance checklist

### 6.3 Launch
**Goal:** Public release

**Tasks:**
- [ ] Production deployment setup
- [ ] Monitoring and alerting (AppSignal/Sentry)
- [ ] Backup and disaster recovery
- [ ] SEO optimization
- [ ] Social media presence
- [ ] Beta user testing
- [ ] Public launch

**Deliverables:**
- Live production system
- Marketing materials
- User feedback loop

## Research & Learning Topics

### Immediate (Phase 1-2)
- [ ] Study Elixir web scraping libraries (Floki, Crawly, HTTPoison)
- [ ] Learn PostgreSQL full-text search
- [ ] Review Ecto best practices for complex queries
- [ ] Research South African job market structure

### Medium-term (Phase 3-4)
- [ ] Study deduplication algorithms in depth
- [ ] Learn about LSH and MinHash implementations
- [ ] Explore NLP for skill extraction (Elixir NLP libraries)
- [ ] Research job classification taxonomies (O*NET)

### Long-term (Phase 5-6)
- [ ] Machine learning for duplicate detection
- [ ] Advanced NLP (embeddings, transformers)
- [ ] Real-time data streaming (Phoenix PubSub)
- [ ] Scalability patterns for Elixir/Phoenix

## Success Criteria

### Phase 1-2 Success
- ✓ Database stores 1,000+ jobs from one source
- ✓ Scraper runs reliably on schedule
- ✓ Data normalization achieves 95%+ success rate

### Phase 3-4 Success
- ✓ Deduplication achieves >90% precision
- ✓ API handles 100+ requests/second
- ✓ Admin dashboard shows real-time metrics

### Phase 5-6 Success
- ✓ Database contains 50,000+ unique jobs
- ✓ 5+ active scraping sources
- ✓ Public launch with 100+ active users

## Open Questions for Discussion

1. **Scraping vs APIs:** Should we prioritize job boards with official APIs?
2. **Data Freshness:** How often should we scrape each source? Daily? Hourly?
3. **Historical Data:** Do we keep old/expired job postings for analytics?
4. **User Features:** What features do job seekers value most?
5. **Monetization:** Free service, ads, premium features, or B2B?
6. **ML Investment:** When to invest in ML models vs rule-based approaches?

## Resources & Tools

### Development Tools
- **Elixir/Phoenix:** Web framework
- **PostgreSQL:** Primary database
- **Oban:** Background job processing
- **Floki:** HTML parsing
- **Tesla/Finch:** HTTP clients
- **ExVCR:** Recording HTTP responses for tests

### Infrastructure
- **Fly.io/Heroku/Render:** Hosting options
- **GitHub Actions:** CI/CD
- **Sentry/AppSignal:** Error tracking
- **Grafana/Prometheus:** Metrics

### External Services (Potential)
- **Geocoding:** Google Maps API, OpenStreetMap
- **Company Data:** Clearbit, LinkedIn API
- **Email:** SendGrid, Mailgun
- **Search:** Algolia, Elasticsearch (if needed)
