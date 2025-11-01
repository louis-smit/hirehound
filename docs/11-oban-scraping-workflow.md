# Oban-Based Scraping Architecture - Detailed Walkthrough

## The Big Picture

Oban acts as our **orchestration engine** for scraping. Instead of manually tracking URLs or writing pagination loops, we use Oban's job queue to:

1. **Distribute work** across multiple concurrent workers
2. **Track progress** automatically (Oban stores job state in PostgreSQL)
3. **Handle failures** with automatic retries
4. **Rate limit** per job board
5. **Avoid duplicates** through Oban's unique job features

---

## The Complete Flow (End-to-End)

### Phase 1: Kickoff - Scheduled Scraping

```elixir
# config/config.exs
config :hirehound, Oban,
  queues: [
    scraping: [limit: 5, rate_limit: [allowed: 100, period: 60]]
  ],
  plugins: [
    {Oban.Plugins.Cron,
      crontab: [
        # Scrape PNet hourly - direct job insertion
        {"0 * * * *", {Hirehound.Workers.ListingCrawler, 
          args: %{url: "https://www.pnet.co.za/jobs", board: "pnet", page: 1}}},
        
        # Scrape LinkedIn every 2 hours (when implemented)
        # {"0 */2 * * *", {Hirehound.Workers.ListingCrawler,
        #   args: %{url: "https://linkedin.com/jobs/search?location=South+Africa", board: "linkedin", page: 1}}},
        
        # Scrape CareerJunction daily at 2am (when implemented)
        # {"0 2 * * *", {Hirehound.Workers.ListingCrawler,
        #   args: %{url: "https://careerjunction.co.za/jobs", board: "careerjunction", page: 1}}}
      ]}
  ]
```

**What happens:**
- **Every hour**, Oban cron plugin **directly inserts** a ListingCrawler job
- No intermediate "kickoff" worker needed
- Args are passed directly to the worker

**Why this approach:**
- ✅ No boilerplate kickoff workers
- ✅ Clear what's being scraped (visible in config)
- ✅ Easy to add new boards (just add crontab entry)
- ✅ Good for 1-5 boards (our current scale)

**Future migration:** When we have 10+ boards, we'll move to database-driven configuration with an admin UI.

**Result:** One Oban job in the `scraping` queue waiting to run.

---

### Phase 2: Listing Page Worker - The Core Loop

```elixir
defmodule Hirehound.Workers.ListingCrawler do
  use Oban.Worker, 
    queue: :scraping,
    unique: [period: 60, fields: [:args]]  # ← Prevents duplicate URLs!
  
  @impl Oban.Worker
  def perform(%Job{args: %{"url" => url, "board" => board}}) do
    # 1. Fetch HTML
    {:ok, html} = Fetcher.fetch_html(url)
    
    # 2. Parse with scraper
    scraper = get_scraper(board)  # Returns PNetScraper module
    {:ok, job_summaries} = scraper.scrape_listing_page(url)
    
    # 3. For EACH job found, enqueue detail page scraper
    Enum.each(job_summaries, fn summary ->
      if summary.detail_url do
        %{url: summary.detail_url, board: board}
        |> Workers.DetailScraper.new(unique: [period: 3600])
        |> Oban.insert()
      end
    end)
    
    # 4. Check pagination - if more pages, enqueue next page
    if scraper.has_next_page?(html) do
      next_url = scraper.next_page_url(html)
      
      %{url: next_url, board: board, page: get_page(url) + 1}
      |> Workers.ListingCrawler.new(unique: [period: 60])
      |> Oban.insert()
    end
    
    :ok
  end
  
  defp get_scraper("pnet"), do: PNetScraper
  defp get_scraper("linkedin"), do: LinkedInScraper
end
```

**What happens:**

1. **Worker picks up job** from queue (automatically, based on `limit: 5`)
2. **Fetches HTML** using our `Fetcher` module (Req + retries)
3. **Parses listing page** - finds 25 jobs on page 1
4. **Enqueues 25 detail page jobs** (one per job found)
5. **Checks for next page** - if exists, enqueues "scrape page 2"
6. **Job completes** - Oban marks it as succeeded

**Parallelization:**
- While this worker is running, **4 other workers** can run simultaneously (`limit: 5`)
- They could be scraping page 2, page 3, detail pages, or other boards!

---

### Phase 3: Detail Page Worker - Extract Full Data

```elixir
defmodule Hirehound.Workers.DetailScraper do
  use Oban.Worker, 
    queue: :processing,  # Different queue!
    unique: [period: 3600, fields: [:args]]
  
  @impl Oban.Worker
  def perform(%Job{args: %{"url" => url, "board" => board}}) do
    # 1. Fetch detail page HTML
    {:ok, html} = Fetcher.fetch_html(url)
    
    # 2. Parse full job data
    scraper = get_scraper(board)
    {:ok, job_data} = scraper.scrape_detail_page(url)
    
    # 3. Normalize data
    {:ok, normalized} = Jobs.Normalization.normalize(job_data)
    
    # 4. Match or create company
    {:ok, company} = Companies.find_or_create_by_name(normalized.company_name)
    
    # 5. Save to database
    {:ok, job_posting} = Jobs.create_posting(
      Map.put(normalized, :company_id, company.id)
    )
    
    # 6. Enqueue downstream processing
    %{job_posting_id: job_posting.id}
    |> Workers.DeduplicationWorker.new()
    |> Oban.insert()
    
    :ok
  end
end
```

**What happens:**
1. **Worker fetches detail page** (e.g., `/jobs/12345`)
2. **Extracts full job description, requirements, salary**
3. **Normalizes data** (clean company names, parse dates)
4. **Creates/finds company** in database
5. **Saves job posting** to `job_postings` table
6. **Enqueues deduplication** for this new job

**Parallelization:**
- This runs in `processing` queue with `limit: 20`
- Can have **20 detail pages processing simultaneously**!

---

## URL Tracking - How We Avoid Re-Scraping

### Built-in Deduplication via `unique` Option

```elixir
# In ListingCrawler
Workers.ListingCrawler.new(
  %{url: "https://pnet.co.za/jobs?page=2"},
  unique: [period: 60, fields: [:args]]  # ← Magic happens here!
)
|> Oban.insert()
```

**What `unique` does:**
- Oban **hashes the args** (`url` field)
- **Checks if identical job exists** in last 60 seconds
- If exists: **Discards duplicate**, returns existing job
- If new: **Inserts job** into queue

**Result:** If pagination accidentally enqueues page 2 twice, Oban only processes it once!

### Database-Level Tracking

We also track in our schema:

```elixir
# Migration: add scraping log table
create table(:scraping_logs) do
  add :url, :string, null: false
  add :board, :string, null: false
  add :status, :string  # "success", "failed", "in_progress"
  add :last_scraped_at, :utc_datetime
  add :jobs_found, :integer
  
  timestamps()
end

create index(:scraping_logs, [:url, :board])
create index(:scraping_logs, [:last_scraped_at])
```

**Before enqueueing, check log:**

```elixir
defp should_scrape?(url) do
  case Repo.get_by(ScrapingLog, url: url) do
    nil -> true  # Never scraped
    %{last_scraped_at: scraped_at} ->
      # Re-scrape if > 24 hours old
      DateTime.diff(DateTime.utc_now(), scraped_at, :hour) > 24
  end
end
```

---

## Parallelization Strategy

### Queue Configuration

```elixir
config :hirehound, Oban,
  queues: [
    scraping: [limit: 5],      # 5 concurrent HTTP fetches
    processing: [limit: 20],   # 20 concurrent processors
    deduplication: [limit: 10] # 10 concurrent dedup checks
  ]
```

**At any moment:**
- **5 listing pages** being scraped
- **20 detail pages** being processed
- **10 jobs** being deduplicated
- **Total: 35 concurrent workers**

### Rate Limiting Per Board

```elixir
# For PNet: 100 requests per minute
scraping: [
  limit: 5,
  rate_limit: [allowed: 100, period: 60]
]
```

**How it works:**
- Oban **tracks requests per minute**
- After 100 jobs in 60 seconds, **pauses queue**
- Resumes automatically after rate limit window

**Per-board rate limits:**

```elixir
# Different rate limits per board
defp get_queue_for_board("pnet"), do: :scraping_pnet
defp get_queue_for_board("linkedin"), do: :scraping_linkedin

config :hirehound, Oban,
  queues: [
    scraping_pnet: [limit: 5, rate_limit: [allowed: 100, period: 60]],
    scraping_linkedin: [limit: 2, rate_limit: [allowed: 30, period: 60]]
  ]
```

---

## Example: Scraping PNet from Start to Finish

### Timeline Visualization

```
T+0s:  Cron directly inserts ListingCrawler job (page 1)

T+1s:  Worker picks up page 1 job
       ├─> Fetches HTML
       ├─> Finds 25 jobs
       ├─> Inserts 25 DetailScraper jobs
       └─> Inserts ListingCrawler job (page 2)

T+2s:  5 DetailScrapers start (limit: 5)
       Worker picks up page 2 job
       └─> Finds 25 more jobs, inserts 25 DetailScraper jobs

T+3s:  First DetailScraper completes
       ├─> Saves job to database
       └─> Inserts DeduplicationWorker job

T+4s:  New DetailScraper starts (slot freed)
       DeduplicationWorker starts
       └─> Checks for duplicates

... continues until all pages scraped
```

### Final State (After 1 Hour)

**Oban Jobs Table:**
- 639 ListingCrawler jobs (completed) - one per page
- ~15,000 DetailScraper jobs (completed) - 25 per page × 639 pages
- ~15,000 DeduplicationWorker jobs (completed)

**Our Database:**
- ~12,000 unique job postings (after deduplication)
- ~800 unique companies
- 639 scraping log entries

---

## Advanced: Workflow Orchestration

For complex multi-step processing, we use **Oban Pro Workflows**:

```elixir
defmodule Hirehound.Workflows.JobIngestion do
  use Oban.Pro.Workers.Workflow
  
  def process(%{args: %{"job_posting_id" => id}}) do
    Workflow.new()
    # Step 1: Parse raw data
    |> Workflow.add(:parse, ParseWorker.new(%{id: id}))
    
    # Step 2: Normalize (depends on parse)
    |> Workflow.add(:normalize, NormalizeWorker.new(%{id: id}), 
        deps: [:parse])
    
    # Step 3: Deduplicate (depends on normalize)
    |> Workflow.add(:deduplicate, DeduplicationWorker.new(%{id: id}),
        deps: [:normalize])
    
    # Step 4: Index (depends on deduplicate)
    |> Workflow.add(:index, IndexWorker.new(%{id: id}),
        deps: [:deduplicate])
  end
end
```

**Benefits:**
- **Automatic dependency resolution** - parse must finish before normalize
- **Parallel execution** - if multiple jobs, all parse in parallel, then all normalize
- **Failure isolation** - if deduplication fails, can retry without re-parsing

---

## Monitoring & Observability

### Oban Web Dashboard

```elixir
# In router.ex
scope "/admin" do
  pipe_through [:browser, :require_admin]
  
  forward "/oban", Oban.Web.Router
end
```

**What you see:**
- **Queue depths** - How many jobs waiting
- **Success rates** - % of jobs that succeeded
- **Execution times** - Average time per worker
- **Failed jobs** - Inspect and retry manually
- **Scheduled jobs** - See upcoming cron jobs

### Custom Metrics

```elixir
defmodule Hirehound.Metrics do
  def scraping_stats do
    %{
      jobs_scraped_last_hour: count_jobs_last_hour(),
      active_workers: Oban.check_queue(:scraping).running,
      queue_depth: Oban.check_queue(:scraping).available,
      avg_scrape_time: calculate_avg_time(),
      success_rate: calculate_success_rate()
    }
  end
end
```

---

## Comparison to Hop

| Aspect | Hop | Our Oban Approach |
|--------|-----|-------------------|
| **Parallelization** | Manual (Task.async_stream) | Built-in (queue limits) |
| **URL Tracking** | Manual (need to build) | Automatic (unique jobs) |
| **Pagination** | Built-in (stream-based) | Manual (enqueue next page) |
| **Rate Limiting** | Manual | Built-in (per queue) |
| **Retries** | Manual | Automatic (exponential backoff) |
| **Monitoring** | None | Oban Web dashboard |
| **Durability** | In-memory (lose on crash) | PostgreSQL (survives crashes) |
| **Job State** | Ephemeral | Persistent (query anytime) |
| **Suitable for** | Livebook, small scripts | Production, large-scale |

---

## Key Takeaways

✅ **Oban is our orchestration backbone** - manages all async work  
✅ **Jobs are self-contained** - each worker does one thing  
✅ **Parallelization is natural** - just set `limit` per queue  
✅ **URL tracking is automatic** - via `unique` jobs + scraping logs  
✅ **Pagination is a loop** - each page enqueues the next  
✅ **Fault-tolerant** - jobs survive crashes, auto-retry on failure  
✅ **Observable** - Oban Web shows everything happening in real-time  

**No manual state management needed!** Oban + PostgreSQL handles it all.
