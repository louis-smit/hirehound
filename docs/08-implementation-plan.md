# Implementation Plan - Getting Started

## Current State

✅ **Completed:**
- Phoenix application scaffolded
- Documentation complete (8 detailed docs)
- Standard libraries installed (Req, Oban)
- Development practices defined
- Architecture designed

## Phase 1: Database Foundation (Start Here!)

### Goal: Set up the core data model for organizations and job postings

### Tasks (in order)

#### 1.1 Create Organizations Schema

```bash
# Generate the migration and schema
mix phx.gen.schema Organizations.Organization organizations \
  slug:string:unique \
  canonical_name:string \
  legal_name:string \
  trading_name:string \
  description:text \
  industry:string \
  headquarters_country:string \
  headquarters_province:string \
  headquarters_city:string \
  website_url:string \
  linkedin_url:string \
  quality_score:integer \
  duplicate_cluster_id:uuid \
  is_canonical:boolean \
  raw_data:map \
  --no-context
```

**Then manually add:**
- JSONB fields (`name_variations`, `industry_tags`, `office_locations`)
- Vector field for embeddings (if using pgvector)
- Indexes (name, domain, cluster_id)
- Full-text search vector (tsvector)

**Test in IEx:**
```elixir
iex -S mix
iex> alias Hirehound.Organizations.Organization
iex> %Organization{canonical_name: "Google"} |> Repo.insert()
```

#### 1.2 Create Job Postings Schema

```bash
mix phx.gen.schema Jobs.JobPosting job_postings \
  source_id:string \
  source_name:string \
  source_url:string \
  title:string \
  description:text \
  job_type:string \
  location_type:string \
  province:string \
  city:string \
  organization_id:references:organizations \
  posted_date:utc_datetime \
  quality_score:integer \
  duplicate_cluster_id:uuid \
  is_canonical:boolean \
  raw_data:map \
  --no-context
```

**Then manually add:**
- JSONB fields (`required_skills`, `preferred_skills`, `benefits`)
- Salary fields (min, max, currency, period)
- Experience/education enums
- Indexes
- Foreign key constraints

**Test in IEx:**
```elixir
iex> alias Hirehound.Jobs.JobPosting
iex> org = Repo.get_by(Organization, canonical_name: "Google")
iex> %JobPosting{title: "Senior Developer", organization_id: org.id} |> Repo.insert()
```

#### 1.3 Create Duplicate Clusters Schema

```bash
mix phx.gen.schema Deduplication.DuplicateCluster duplicate_clusters \
  entity_type:string \
  canonical_entity_id:uuid \
  member_count:integer \
  confidence_score:decimal \
  --no-context
```

**Then add:**
- `duplicate_relationships` table for tracking pairwise similarities

#### 1.4 Run Migrations and Verify

```bash
mix ecto.migrate

# Test in IEx
iex -S mix
iex> Repo.all(Organization) |> length()
0  # ✓ Table exists
```

---

## Phase 2: First Scraper (IEx-First Approach)

### Goal: Build one working scraper for PNet using IEx-first methodology

### Tasks (in order)

#### 2.1 Manual Exploration in IEx

**Do NOT write code yet!** Start in IEx:

```elixir
$ iex -S mix

# 1. Fetch a listing page
iex> url = "https://www.pnet.co.za/jobs"
iex> {:ok, response} = Req.get(url)

# 2. Inspect HTML
iex> response.body |> String.slice(0, 500)

# 3. Check if it's listing or detail page
iex> doc = Floki.parse_document!(response.body)
iex> cards = Floki.find(doc, ".job-result")  # Try different selectors
iex> length(cards)  # > 1 = listing page

# 4. Extract data from first job
iex> first = List.first(cards)
iex> title = Floki.find(first, "h3") |> Floki.text()
iex> company = Floki.find(first, ".company-name") |> Floki.text()

# 5. Document what selectors work
# Write down: "Job cards are .job-result, title is h3, company is .company-name"
```

**Deliverable:** Notes on CSS selectors that work for PNet

#### 2.2 Create Scraper Module

**Only after IEx exploration works!**

```bash
# Create behaviour file
touch lib/hirehound/scrapers/behaviour.ex

# Create PNet scraper
touch lib/hirehound/scrapers/pnet_scraper.ex
```

**Copy working IEx code into modules**

**Test in IEx:**
```elixir
iex> recompile()
iex> alias Hirehound.Scrapers.PNetScraper
iex> {:ok, jobs} = PNetScraper.scrape_listing_page("https://www.pnet.co.za/jobs")
iex> jobs |> List.first() |> IO.inspect()
```

#### 2.3 Write Tests

```elixir
# test/hirehound/scrapers/pnet_scraper_test.exs
defmodule Hirehound.Scrapers.PNetScraperTest do
  use ExUnit.Case
  use ExVCR.Mock
  
  test "scrapes PNet listing page" do
    use_cassette "pnet_listing_page" do
      {:ok, jobs} = PNetScraper.scrape_listing_page("https://www.pnet.co.za/jobs")
      assert length(jobs) > 0
    end
  end
end
```

Run test once to record HTTP response, then it replays from fixture.

#### 2.4 Add URL-Based Routing

**After scraper works:**

1. Implement `url_patterns/0` in PNetScraper
2. Create `Scrapers.Registry` GenServer
3. Create `Scraper.scrape_url/1` wrapper
4. Test both patterns work

**Test in IEx:**
```elixir
iex> PNetScraper.scrape_listing_page("https://pnet.co.za/jobs")  # Direct
{:ok, [...]}

iex> Scraper.scrape_url("https://pnet.co.za/jobs")  # Auto-routed
{:ok, [...]}

iex> Scraper.which_scraper("https://pnet.co.za/jobs")
{:ok, Hirehound.Scrapers.PNetScraper, :listing}  # ✓
```

---

## Phase 3: Data Normalization & Organization Matching

### Goal: Process raw scraped data into normalized entities

### Tasks

#### 3.1 Organization Name Matcher (IEx-first!)

```elixir
# In IEx first
iex> raw_company = "Google (Pty) Ltd"
iex> normalized = raw_company |> String.downcase() |> String.replace(~r/\(pty\) ltd/, "")
"google"

# Search for match
iex> Repo.get_by(Organization, canonical_name: "google")

# Test fuzzy matching
iex> String.jaro_distance("google", "Google South Africa")
```

**Then codify:**
```bash
touch lib/hirehound/organizations/name_matcher.ex
```

#### 3.2 Job Normalization Pipeline

**Create:**
- `lib/hirehound/jobs/normalization.ex`
- Functions for title, location, date parsing
- Test each function in IEx before writing tests

#### 3.3 Integration: Save Scraped Jobs

**In IEx:**
```elixir
iex> {:ok, raw_jobs} = PNetScraper.scrape_listing_page(url)
iex> first_raw = List.first(raw_jobs)

# Find or create organization
iex> {:ok, org} = Organizations.find_or_create_by_name(first_raw.company)

# Normalize job
iex> normalized = Jobs.Normalization.normalize(first_raw)

# Save to database
iex> %JobPosting{}
     |> JobPosting.changeset(Map.put(normalized, :organization_id, org.id))
     |> Repo.insert()
```

**Then codify into `Jobs.Ingestion.process_raw_job/1`**

---

## Phase 4: Basic Deduplication

### Goal: Implement exact duplicate detection only (simplest stage)

### Tasks

#### 4.1 Exact Hash Matching (IEx-first!)

```elixir
# In IEx
iex> job1 = Repo.get(JobPosting, "some-uuid")
iex> normalized = "#{job1.title}|#{job1.organization_id}|#{job1.city}"
iex> hash = :crypto.hash(:md5, normalized) |> Base.encode16()

# Find duplicates
iex> Repo.get_by(JobPosting, combined_hash: hash)
```

**Then codify:**
```bash
touch lib/hirehound/deduplication/exact_matcher.ex
```

#### 4.2 Add Hash Field to Schema

```bash
mix ecto.gen.migration add_combined_hash_to_job_postings
```

Add: `add :combined_hash, :string` + index

#### 4.3 Test Deduplication

**Create duplicate job in IEx:**
```elixir
iex> org = Repo.get_by(Organization, canonical_name: "google")
iex> job1 = %JobPosting{title: "Dev", organization_id: org.id} |> Repo.insert!()
iex> job2 = %JobPosting{title: "Dev", organization_id: org.id} |> Repo.insert!()

# Run deduplication
iex> Deduplication.ExactMatcher.find_duplicates(job1)
[job2]  # ✓ Found it!
```

---

## Phase 5: Background Jobs & Automation

### Goal: Automate scraping with Oban

### Tasks

#### 5.1 Create Scraping Worker

```bash
touch lib/hirehound/workers/pnet_scraping_worker.ex
```

```elixir
defmodule Hirehound.Workers.PNetScrapingWorker do
  use Oban.Worker, queue: :scraping
  
  @impl Oban.Worker
  def perform(%Job{args: %{"url" => url}}) do
    PNetScraper.scrape_listing_page(url)
  end
end
```

#### 5.2 Test Worker in IEx

```elixir
iex> %{url: "https://www.pnet.co.za/jobs"}
     |> Hirehound.Workers.PNetScrapingWorker.new()
     |> Oban.insert()

# Check job executed
iex> Repo.all(Oban.Job)
```

#### 5.3 Schedule Periodic Scraping

Configure Oban cron in `config/config.exs`:

```elixir
config :hirehound, Oban,
  queues: [scraping: 10, processing: 20],
  plugins: [
    {Oban.Plugins.Cron,
      crontab: [
        {"0 * * * *", Hirehound.Workers.PNetScrapingWorker}  # Hourly
      ]}
  ]
```

---

## Immediate Next Steps (This Week)

### Priority 1: Database Setup ⚡

1. [ ] Run schema generators for organizations and job postings
2. [ ] Manually customize migrations (add JSONB, indexes)
3. [ ] Run migrations
4. [ ] Test creating entities in IEx

**Time estimate:** 2-3 hours

### Priority 2: First Scraper (IEx-First) ⚡

1. [ ] Start IEx, manually scrape PNet in REPL
2. [ ] Document CSS selectors that work
3. [ ] Create behaviour module
4. [ ] Create PNet scraper module (copy IEx code)
5. [ ] Test in IEx again
6. [ ] Write ExVCR tests

**Time estimate:** 4-6 hours

### Priority 3: Basic Integration ⚡

1. [ ] Build organization name matcher
2. [ ] Build job normalization
3. [ ] Integrate: scrape → normalize → save to DB
4. [ ] Test end-to-end in IEx

**Time estimate:** 3-4 hours

**Total Week 1:** ~10-13 hours to working scraper saving to database

---

## Questions to Answer First

Before starting implementation:

### Technical Questions

1. **Oban Pro license:** Do we have budget for Oban Pro (~$500-2000/year)?
   - If no: Use free Oban, chain jobs manually
   - If yes: Use Oban Pro Workflows from the start

2. **pgvector for embeddings:** Do we need semantic search immediately?
   - If no: Skip vectorization for now
   - If yes: Install pgvector extension

3. **ExVCR vs manual fixtures:** Should we record HTTP responses or create fixtures?
   - Recommend: ExVCR (easier, more realistic)

### Process Questions

1. **Should I build features or wait for direction?**
   - Recommend: Build Phase 1 (database) now, then check in

2. **How do you want to review progress?**
   - After each phase?
   - Daily check-ins?
   - When stuck?

---

## Proposed Workflow for Next Session

### Option A: I Build Foundation (Autonomous)

**You say:** "Go ahead and implement Phase 1 (database schemas)"

**I do:**
1. Generate schemas with `mix phx.gen.schema`
2. Customize migrations
3. Run migrations
4. Test in IEx
5. Report back with what I built

**Time:** 1-2 hours of your time reviewing

### Option B: We Build Together (Collaborative)

**You say:** "Let's build the PNet scraper together"

**We do:**
1. You paste a PNet URL
2. I explore it in IEx (you see the process)
3. I create the modules
4. You review and approve
5. We iterate

**Time:** 2-3 hours pair programming

### Option C: You Explore, I Document (Guided)

**You say:** "I'm exploring PNet in IEx, here's what I found..."

**You do:** Manual IEx exploration
**I do:** Document findings, create modules based on your notes

**Time:** Flexible, async

---

## My Recommendation

**Start with Option A:**

1. **Let me build the database schemas** (Phase 1.1-1.4)
   - Low risk, well-defined
   - Easy to review (just migrations)
   - Sets foundation for everything else

2. **Then switch to Option B** for first scraper
   - More fun to build together
   - Critical to get scraping patterns right
   - Good learning experience

3. **Then back to Option A** for automation
   - I build workers/jobs
   - You review and test

---

## What Do You Think?

**Questions for you:**

1. Should I proceed with building the database schemas now?
2. Do we have/need Oban Pro license, or use free Oban?
3. Any specific job board you want to start with (PNet, LinkedIn, other)?
4. Want me to create a GitHub project board / issue tracking for this?

**I'm ready to start coding when you are!** 🚀
