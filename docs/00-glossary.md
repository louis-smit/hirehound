# Glossary & Terminology

This document defines key terms and concepts used throughout the Hirehound documentation.

---

## Core Entities

### Job Posting
An individual job advertisement/vacancy scraped from a job board. Each posting is a separate database record, even if it represents the same real-world job on multiple sites.

**Example:** A "Senior Developer" role at Company X posted on both PNet and LinkedIn creates **two job postings** in our database.

**Related terms:** Job advertisement, vacancy, position

**NOT to be confused with:** "Job listing" (less accurate term we avoid)

### Listing Page vs Detail Page ⚠️ IMPORTANT

**Critical distinction for scrapers:**

**Listing Page (Index Page)**
- A page that displays **multiple jobs** (search results, category page)
- Contains **summary information** for each job (title, company, location)
- May or may not have full job details
- Examples:
  - `https://www.pnet.co.za/jobs` (shows 20+ jobs)
  - `https://www.pnet.co.za/jobs?category=it&page=2`
  - `https://careers.company.com/openings`

**Detail Page (Job Page)**
- A page for **one specific job** with full information
- Contains complete job description, requirements, application details
- Usually has unique ID in URL
- Examples:
  - `https://www.pnet.co.za/jobs/12345`
  - `https://careers.company.com/openings/senior-developer-cape-town`
  - `https://www.linkedin.com/jobs/view/3456789`

**Why this matters:**
- ❌ **Common mistake:** Writing a scraper that expects multiple jobs but receives detail page (or vice versa)
- ❌ **Wrong:** Using detail page selectors on listing page
- ✅ **Correct:** Separate functions/logic for listing vs detail pages

**Scraping patterns:**
1. **Two-stage scraping:** Scrape listing pages to get job URLs → scrape detail pages for full data
2. **Listing-only scraping:** If listing page has enough info, skip detail pages
3. **Hybrid:** Get basics from listing, enrich from detail page if needed

### Organization
A company, employer, or hiring entity. Organizations are **first-class entities** in Hirehound with their own profiles, independent of job postings.

**Example:** "Google South Africa (Pty) Ltd" is one organization that may have many job postings.

**Related terms:** Company, employer, hiring organization

### Source
The origin of scraped data - typically a job board or website.

**Examples:** PNet, LinkedIn, CareerJunction, Indeed

**Database field:** `source_name` (e.g., "pnet", "linkedin")

---

## Deduplication Concepts

### Duplicate
Multiple database records that represent the same real-world entity.

**Job Posting Example:** Same job appearing on PNet, LinkedIn, and CareerJunction = 3 duplicate postings

**Organization Example:** "ABC Company (Pty) Ltd", "ABC Company", "ABC Co." = 3 duplicate organization records

### Cluster
A **group of duplicate entities** linked together because they represent the same real-world thing.

**Structure:**
```
Cluster #42
├── Job Posting A (PNet)      [canonical ✓]
├── Job Posting B (LinkedIn)
└── Job Posting C (CareerJunction)
```

**Database representation:** All members share the same `duplicate_cluster_id`

**Related terms:** Duplicate group, entity cluster

### Canonical (Entity)
The **primary or "best" member** of a duplicate cluster. This is the entity chosen to represent the cluster in search results and user interfaces.

**Selection criteria:**
1. Highest data quality/completeness
2. Most authoritative source
3. Most recent
4. Longest/most detailed description

**Database field:** `is_canonical = true`

### Clustering
The **process of grouping duplicates** into clusters. Uses graph-based algorithms (connected components) to find all related entities.

**Example workflow:**
1. Find all pairs of duplicates (edges in a graph)
2. Find connected components (groups where A→B→C forms a cluster)
3. Assign cluster IDs to all members
4. Select canonical member for each cluster

### Exact Duplicate
Entities with **byte-for-byte identical or near-identical** content after normalization.

**Detection method:** Hash-based comparison (MD5/SHA of normalized data)

**Example:** Same job posting copy-pasted to multiple sites with identical text

### Near Duplicate
Entities with **very similar content** but minor textual differences.

**Detection method:** MinHash, LSH (Locality-Sensitive Hashing), Jaccard similarity

**Example:** Same job description with slight formatting differences or added/removed sentences

**Similarity threshold:** Typically 85%+ similarity

### Fuzzy Duplicate
Entities that represent the same thing but with **significant textual variations**.

**Detection method:** Multi-signal scoring combining:
- Title similarity (Levenshtein distance)
- Company match
- Location match
- Description similarity (TF-IDF, embeddings)
- Temporal proximity

**Example:** Same job reposted with rewritten description, or organization with different legal name format

**Similarity threshold:** Typically 70-80%

### Blocking
A **performance optimization** technique that narrows down candidates for comparison, avoiding O(n²) comparisons.

**How it works:** Only compare entities that share certain "blocking keys"

**Job posting blocking keys:**
- Same organization
- Same province/city
- Posted within 30 days

**Organization blocking keys:**
- Same first letter of name
- Same province
- Same industry

**Result:** Instead of comparing every job to every other job (millions of comparisons), we only compare ~100 candidates per job.

---

## Data Processing Concepts

### Normalization
The process of **converting raw scraped data into a standardized format**.

**Examples:**
- Company names: "Google (Pty) Ltd" → "Google"
- Locations: "CPT" → "Cape Town, Western Cape"
- Dates: "Posted 2 days ago" → ISO 8601 timestamp
- Job titles: Remove company names, standardize abbreviations

**Purpose:** Enable accurate matching and querying across sources

### Enrichment
**Adding additional data** to an entity from external sources or derived information.

**Organization enrichment sources:**
- LinkedIn API (employee count, description)
- Clearbit (company metadata)
- Company registry (registration numbers)
- Logo scraping

**Job posting enrichment:**
- Skill extraction from description
- Salary estimation (if missing)
- Location geocoding

**Database field:** `enrichment_status` (pending, in_progress, complete, failed)

### Scraping
The automated process of **extracting data from job board websites**.

**Methods:**
- HTML parsing (Floki)
- CSS selectors
- XPath queries
- API calls (when available)

**Challenges:** Rate limiting, anti-bot measures, changing HTML structure

### Vectorization / Embeddings
Converting text into **numerical vectors** (arrays of numbers) that capture semantic meaning.

**Purpose:** Enable semantic search - find similar jobs/organizations based on meaning, not just keywords

**Example:**
```
"Senior Software Engineer" → [0.234, -0.567, 0.891, ...]
"Lead Developer"           → [0.241, -0.554, 0.876, ...]
```
These vectors are close together (similar meaning) even with different words.

**Models used:** BERT, sentence transformers, or OpenAI embeddings

**Storage:** PostgreSQL pgvector extension

### RAG (Retrieval-Augmented Generation)
**Combining vector search with AI generation** for intelligent question answering.

**Example use case:** "Find me remote Python jobs at fintech companies"
1. Vectorize the query
2. Find similar job postings using vector similarity
3. (Future) Use LLM to summarize/filter results

**In Hirehound:** Primarily using the "retrieval" part for semantic job search

---

## Data Quality Concepts

### Quality Score
A **0-100 metric** indicating how complete and accurate an entity's data is.

**Factors for job postings:**
- Has all required fields (title, description, organization)
- Has optional fields (salary, requirements, closing date)
- Text quality (length, formatting)
- No missing/null values

**Factors for organizations:**
- Contact information present
- External data enriched (LinkedIn, website)
- Logo available
- Description completeness

**Database field:** `quality_score` (integer, 0-100)

### Fingerprint
A **compact representation** of an entity used for fast similarity comparison.

**Types:**
- **Hash fingerprint:** MD5/SHA hash for exact matching
- **MinHash fingerprint:** Set of hash values for near-duplicate detection
- **Title fingerprint:** Normalized title for fuzzy matching

**Purpose:** Faster comparisons than full text comparison

### Alias
An **alternative name or spelling** for an organization.

**Examples for "International Business Machines":**
- Primary: "IBM"
- Aliases: "International Business Machines", "IBM Corporation", "Big Blue"

**Types:**
- Legal name
- Trading name
- Acronym
- Former name
- Common misspelling

**Database:** `organization_aliases` table

---

## Technical Architecture Concepts

### Workflow / Pipeline
A **multi-step process** with dependencies between steps, orchestrated as a sequence of background jobs.

**Example - Job Ingestion Pipeline:**
```
Scrape → Parse → Normalize → Match Org → Extract Skills → 
Vectorize → Deduplicate → Cluster → Index → Publish
```

**Managed by:** Oban Pro Workflow engine

**Features:** Conditional branching, parallel execution, retries, dependencies

### Worker
A **background job processor** that performs a specific task asynchronously.

**Examples:**
- `JobScraperWorker` - Scrapes a job board
- `DeduplicationWorker` - Finds duplicates
- `VectorizationWorker` - Generates embeddings
- `OrganizationEnrichmentWorker` - Fetches external data

**Managed by:** Oban job queue system

### Queue
A **named channel** for background jobs with specific concurrency and rate limits.

**Hirehound queues:**
- `scraping` - Web scraping jobs (rate-limited)
- `processing` - Data processing
- `deduplication` - Duplicate detection
- `ml` - Machine learning tasks (vectorization)
- `indexing` - Search index updates
- `enrichment` - External API calls

**Configuration:** Queue limits, priorities, rate limits per queue

### Batch Processing
Processing **multiple entities together** for efficiency.

**Example:** Instead of deduplicating jobs one-by-one, process 100 jobs as a batch, then run clustering on all results together.

**Benefit:** Reduces database queries, enables bulk operations

**Managed by:** Oban Pro Batch workers

---

## Search & Matching Concepts

### Full-Text Search
**Keyword-based search** using PostgreSQL's text search capabilities.

**How it works:**
- Text converted to `tsvector` (searchable tokens)
- Queries converted to `tsquery`
- Ranking based on term frequency and position

**Database field:** `search_vector` (tsvector type)

**Use case:** "Find jobs containing 'python' OR 'django'"

### Semantic Search
**Meaning-based search** using vector embeddings and similarity.

**How it works:**
- Convert query to embedding vector
- Find nearest vectors in database (cosine similarity)
- Return top-K most similar entities

**Use case:** "remote developer opportunities" matches "work from home software engineer jobs"

**Advantage:** Understands synonyms, related concepts, and intent

### MinHash
An algorithm for **fast near-duplicate detection** using hashing.

**How it works:**
1. Break text into shingles (word n-grams)
2. Hash each shingle
3. Keep minimum hash values
4. Compare MinHash signatures (Jaccard similarity)

**Benefit:** O(1) comparison time instead of O(n) for full text comparison

**Use case:** Detecting near-duplicate job descriptions

### LSH (Locality-Sensitive Hashing)
A technique for **fast approximate nearest neighbor search**.

**How it works:** Hash similar items to the same bucket, enabling quick candidate generation

**Use case:** Finding similar job postings without comparing all pairs

**Benefit:** Makes near-duplicate detection scalable to millions of entities

---

## Database Concepts

### JSONB
PostgreSQL's **JSON binary format** for storing semi-structured data.

**Use cases in Hirehound:**
- `raw_data` - Original scraped JSON
- `skills` - Array of extracted skills
- `benefits` - List of job benefits
- `office_locations` - Array of office addresses
- `processing_notes` - Warnings/errors during processing

**Benefits:** Flexible schema, queryable with SQL, indexed

### tsvector
PostgreSQL's **full-text search vector** data type.

**Purpose:** Optimized storage of searchable text with term positions and weights

**Generation:** Automatically from text columns using triggers or explicit updates

**Index:** GIN or GiST index for fast search

### pgvector
PostgreSQL extension for **storing and querying vector embeddings**.

**Data type:** `vector(n)` where n is dimensionality (e.g., 768 for BERT)

**Operations:**
- Cosine similarity: `<=>` operator
- Euclidean distance: `<->` operator
- Inner product: `<#>` operator

**Index:** HNSW (Hierarchical Navigable Small World) for fast nearest neighbor search

### PostGIS
PostgreSQL extension for **geographic/spatial data**.

**Use cases:**
- Store office coordinates: `POINT(lat, lng)`
- Calculate distances between locations
- Geographic queries: "jobs within 50km of Cape Town"

**Data types:** `geography`, `geometry`

---

## Workflow Orchestration Concepts

### Oban
An **Elixir/PostgreSQL-based background job processing** library.

**Features:**
- Reliable job execution
- Retries with exponential backoff
- Scheduled/cron jobs
- Job prioritization
- Dead letter queue

**Why Oban:** Native Elixir, uses PostgreSQL (no Redis needed), excellent observability

### Oban Pro
**Commercial extension** of Oban with advanced features.

**Key features:**
- Workflow engine (multi-step pipelines)
- Batch processing
- Rate limiting
- Dynamic queue management
- Advanced metrics

**Used for:** Complex multi-step processes (ingestion, deduplication)

### Circuit Breaker
A **failure protection pattern** that prevents cascading failures.

**How it works:**
1. **Closed:** Requests go through normally
2. **Open:** After N failures, stop trying (fail fast)
3. **Half-open:** After timeout, try again; if succeeds, close; if fails, reopen

**Use case:** Protect against external API failures (LinkedIn, Clearbit)

**Library:** Fuse (Elixir circuit breaker)

### Dead Letter Queue (DLQ)
A **holding area for jobs that failed permanently** after all retries.

**Purpose:** 
- Prevent job loss
- Enable manual investigation
- Track systemic issues

**Process:**
1. Job fails max_attempts times
2. Move to dead_letter_jobs table
3. Alert sent to ops team
4. Manual review/reprocessing

---

## Business/Domain Concepts

### Spam Detection
Identifying and filtering **fake, low-quality, or fraudulent job postings**.

**Detection methods:**
- Rule-based (suspicious keywords, patterns)
- ML classification (trained on labeled examples)
- Similarity to known spam

**Spam indicators:**
- Too-good-to-be-true salary
- Vague job description
- External links to suspicious sites
- Posted by unverified organizations

### Job Type
The **employment classification** of a position.

**Values (ENUM):**
- `full_time` - Permanent, full-time role
- `part_time` - Part-time employment
- `contract` - Fixed-term contract
- `temporary` - Short-term/seasonal
- `internship` - Internship program
- `freelance` - Freelance/consulting

### Location Type
The **work arrangement** regarding location.

**Values (ENUM):**
- `onsite` - Work from office/location
- `remote` - Work from anywhere
- `hybrid` - Combination of office and remote

### Experience Level
The **seniority or experience required** for a role.

**Values (ENUM):**
- `entry` - Entry-level, graduate positions
- `intermediate` - Mid-level, some experience
- `senior` - Senior-level, extensive experience
- `lead` - Lead/principal level
- `executive` - C-level, director positions

---

## Metrics & Monitoring

### Precision
In duplicate detection: **Percentage of identified duplicates that are actually duplicates**.

**Formula:** `True Positives / (True Positives + False Positives)`

**Example:** If we flag 100 job pairs as duplicates, and 95 are correct, precision = 95%

**Goal:** > 90% (avoid false positives)

### Recall
In duplicate detection: **Percentage of actual duplicates that we successfully identified**.

**Formula:** `True Positives / (True Positives + False Negatives)`

**Example:** If there are 100 actual duplicate pairs, and we find 80, recall = 80%

**Goal:** > 85% (don't miss too many duplicates)

**Trade-off:** Higher precision often means lower recall (and vice versa)

### Throughput
**Number of entities processed per unit time**.

**Examples:**
- Jobs scraped per hour
- Deduplication operations per minute
- Search queries per second

**Monitoring:** Track to ensure system keeps up with incoming data

### Queue Depth
**Number of jobs waiting in a queue** to be processed.

**Monitoring:**
- Normal: < 100 jobs
- Warning: > 1,000 jobs (falling behind)
- Critical: > 10,000 jobs (serious backlog)

**Action:** Scale up workers if consistently high

---

## Related Technologies

### Elixir
**Functional programming language** built on the Erlang VM (BEAM).

**Why Elixir:**
- Excellent concurrency (millions of processes)
- Fault-tolerant (OTP supervision trees)
- Great for scraping/background processing
- Phoenix framework for web apps

### Phoenix
**Web framework** for Elixir.

**Components we use:**
- Phoenix (web server, API)
- Ecto (database wrapper/ORM)
- LiveView (real-time admin dashboards)

### PostgreSQL
**Relational database** with advanced features.

**Extensions we use:**
- pgvector - Vector embeddings
- PostGIS - Geographic data
- Full-text search (built-in)

**Why PostgreSQL:** Mature, reliable, rich feature set, great for complex queries

### Floki
**HTML parsing library** for Elixir.

**Use case:** Parse scraped job board HTML to extract structured data

**Similar to:** BeautifulSoup (Python), Cheerio (JavaScript)

---

## Quick Reference

| Term | One-line Definition |
|------|-------------------|
| **Cluster** | Group of duplicate entities representing the same real-world thing |
| **Canonical** | The "primary" or "best" entity in a duplicate cluster |
| **Blocking** | Limiting comparisons to candidates sharing certain keys |
| **Fingerprint** | Compact representation of an entity for fast comparison |
| **Enrichment** | Adding data from external sources |
| **Vectorization** | Converting text to numerical embeddings |
| **Workflow** | Multi-step background process with dependencies |
| **Quality Score** | 0-100 metric of data completeness |
| **Alias** | Alternative name/spelling for an organization |
| **Precision** | % of detected duplicates that are correct |
| **Recall** | % of actual duplicates that were detected |

---

**Last Updated:** 2024  
**Version:** 1.0.0
