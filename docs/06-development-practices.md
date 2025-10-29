# Development Practices & Workflow

## Philosophy

Hirehound follows an **Elixir-native, iterative, REPL-first** development approach:

✅ **IEx before UI** - Test in the REPL before building interfaces  
✅ **Manual before automated** - Run processes manually before scheduling  
✅ **Protocols over concrete types** - Define behaviors for extensibility  
✅ **Incremental development** - Build one small piece at a time  
✅ **Data-first** - Design data structures before functions  
✅ **Functional core, imperative shell** - Pure functions + side effects at boundaries

## Standard Library Choices

### HTTP Client: Req (NOT HTTPoison)

**Use:** [Req](https://hexdocs.pm/req) - Modern, composable HTTP client

```elixir
# ✅ GOOD: Use Req
response = Req.get!("https://example.com/jobs")

# With middleware/plugins
response = 
  Req.new(base_url: "https://api.example.com")
  |> Req.Request.put_header("user-agent", "Hirehound/1.0")
  |> Req.get!(url: "/jobs")

# ❌ AVOID: HTTPoison (older, less ergonomic)
HTTPoison.get("https://example.com/jobs")
```

**Why Req:**
- Modern, actively maintained
- Better composability with middleware
- Cleaner API
- Built-in retry, rate limiting, caching
- Excellent error handling

### LLM Integration: ReqLLM

**Use:** [ReqLLM](https://github.com/thmsmlr/req_llm) for AI/LLM calls

```elixir
# ✅ GOOD: Use ReqLLM
response = 
  Req.new()
  |> ReqLLM.attach()
  |> Req.post!(
      url: "https://api.openai.com/v1/chat/completions",
      json: %{model: "gpt-4", messages: [...]}
    )

# Streaming support built-in
Req.new()
|> ReqLLM.attach()
|> Req.post!(url: ..., into: :self)
```

**Why ReqLLM:**
- Built on Req (consistent patterns)
- Streaming support
- Structured output parsing
- Token counting
- Multiple provider support

### Workflow Orchestration: Oban (+ Oban Pro)

**Use:** [Oban](https://hexdocs.pm/oban) for background jobs + [Oban Pro](https://getoban.pro) for workflows

```elixir
# ✅ GOOD: Oban for reliable job processing
defmodule Hirehound.Workers.ScrapingWorker do
  use Oban.Worker, queue: :scraping
  
  @impl Oban.Worker
  def perform(%Job{args: %{"url" => url}}) do
    # Simple, deterministic job
    url
    |> fetch_html()
    |> parse_jobs()
    |> save_to_db()
  end
end

# Oban Pro for complex workflows (DAGs with dependencies)
defmodule Hirehound.Workflows.JobIngestion do
  use Oban.Pro.Workers.Workflow
  
  @impl Oban.Pro.Workers.Workflow
  def process(%Job{args: %{"job_posting_id" => id}}) do
    # Build DAG with dependencies
    Workflow.new()
    |> Workflow.add(:parse, ParseWorker.new(%{id: id}))
    |> Workflow.add(:normalize, NormalizeWorker.new(%{id: id}), deps: [:parse])
    |> Workflow.add(:deduplicate, DeduplicateWorker.new(%{id: id}), deps: [:normalize])
    |> Workflow.add(:index, IndexWorker.new(%{id: id}), deps: [:deduplicate])
  end
end
```

**Why Oban (Pro):**
- Reliable, persistent job queue (PostgreSQL-backed)
- Scheduled/cron jobs built-in
- Automatic retries with exponential backoff
- **Workflows (Pro):** DAG orchestration, fan-out/fan-in, conditional logic
- Cluster-safe, distributed
- Excellent observability (Oban Web dashboard)

**Why NOT Jido (for now):**
- ❌ Jido is for **AI-driven agentic systems** (LLM planning, autonomous agents)
- ❌ We need **deterministic pipelines**, not adaptive AI agents
- ✅ If we add AI enrichment later, we can call LLMs from Oban workers
- ✅ Only add Jido if we need agents that *reason* and *adapt* autonomously

**Why NOT Broadway or GenStage:**
- ❌ **Broadway** - Designed for message broker consumption (Kafka/SQS/RabbitMQ)
  - We don't have a broker and don't need one
  - Requires additional infrastructure
  - Only makes sense at >500k-1M events/day with sub-second latency needs
- ❌ **GenStage** - Too low-level, you build durability/retries/scheduling yourself
  - In-memory only (no persistence)
  - Would need to rebuild what Oban provides
- ❌ **Jido** - Designed for agentic AI, not deterministic ETL pipelines
  - Use only if we need LLM-powered agents that plan autonomously
  - For scraping/dedup workflows, Oban is better

**Alternatives considered:**
- ❌ GenStage/Flow - Too low-level for our needs
- ❌ Broadway - Overkill for our data volumes (see [Workflow Orchestration](./05-workflow-orchestration.md))
- ❌ Jido - Designed for agentic AI, not ETL pipelines
- ✅ Oban (Pro) - Perfect fit for job processing + workflow orchestration

### HTML Parsing: Floki

**Use:** [Floki](https://hexdocs.pm/floki) - HTML parser

```elixir
# ✅ GOOD: Use Floki
html
|> Floki.parse_document!()
|> Floki.find(".job-listing")
|> Floki.attribute("data-job-id")
```

**Why Floki:**
- Native Elixir
- CSS selector support
- Fast C-based parser option
- Well-maintained

### Testing: ExUnit + Mox

**Use:** ExUnit (built-in) + Mox for mocks

```elixir
# ✅ GOOD: Use Mox for mocking external APIs
defmodule Hirehound.MockHTTPClient do
  use Mox
  
  defmock(Hirehound.HTTPClientMock, for: Hirehound.HTTPClientBehaviour)
end

# In tests
test "scrapes job board" do
  expect(Hirehound.HTTPClientMock, :get, fn _url ->
    {:ok, %{status: 200, body: "<html>...</html>"}}
  end)
  
  assert {:ok, jobs} = Scraper.scrape("https://example.com")
end
```

**Why Mox:**
- Explicit mocks (no global state)
- Compile-time verification
- Concurrent test support

### HTTP Recording: ExVCR

**Use:** [ExVCR](https://hexdocs.pm/exvcr) to record/replay HTTP interactions

```elixir
# ✅ GOOD: Record real HTTP responses for tests
use ExVCR.Mock, adapter: ExVCR.Adapter.Finch

test "scrapes PNet jobs" do
  use_cassette "pnet_jobs_page" do
    {:ok, jobs} = PNetScraper.scrape()
    assert length(jobs) > 0
  end
end
```

**Why ExVCR:**
- Record real responses once
- Fast test replay
- No network calls in CI
- Catch API changes

## Standard Library Summary

| Purpose | Library | Avoid |
|---------|---------|-------|
| HTTP Client | **Req** | HTTPoison, Finch directly |
| LLM Calls | **ReqLLM** | Custom HTTP code |
| Background Jobs | **Oban** | Exq, Faktory |
| Workflows | **Oban Pro** | GenStage, Broadway, Jido* |
| HTML Parsing | **Floki** | Custom regex parsing |
| Mocking | **Mox** | :meck, global mocks |
| HTTP Recording | **ExVCR** | Manual fixture files |
| Database | **Ecto** | Raw SQL (except when needed) |
| JSON | **Jason** | Poison |
| CSV | **NimbleCSV** | Custom parsers |

**Note on Jido:*** Jido is for AI-driven agentic systems. Only add if you need LLM-powered agents that plan and adapt autonomously. For deterministic ETL pipelines, use Oban Pro Workflows.

---

## Iterative Development Workflow

### Phase 1: IEx Exploration

**Start in the REPL, not in code files.**

**⚠️ CRITICAL: Check if URL is Listing or Detail Page First!**

```elixir
# 1. Start IEx with your app
$ iex -S mix

# 2. First, identify what TYPE of page you're scraping!
iex> listing_url = "https://www.pnet.co.za/jobs"  # Shows MULTIPLE jobs
iex> detail_url = "https://www.pnet.co.za/jobs/12345"  # Shows ONE job

# 3. Manually test - start with listing page
iex> {:ok, response} = Req.get(listing_url)
iex> response.body |> String.slice(0, 200)  # Inspect HTML

# Check: Does this page show multiple jobs or just one?
iex> doc = Floki.parse_document!(response.body)
iex> job_cards = Floki.find(doc, ".job-result-card")
iex> length(job_cards)  # If > 1, it's a listing page ✓

# 3. Experiment with parsing
iex> html = response.body
iex> doc = Floki.parse_document!(html)
iex> jobs = Floki.find(doc, ".job-result-card")
iex> length(jobs)  # How many jobs found?

# 4. Extract data from first job
iex> first_job = List.first(jobs)
iex> title = Floki.find(first_job, ".job-title") |> Floki.text()
iex> company = Floki.find(first_job, ".company-name") |> Floki.text()

# 5. Once patterns work, codify them
```

**Key principle:** Don't write code until you've manually verified it works in IEx.

### Phase 2: Codify into Modules

Once you've validated the approach in IEx, create modules:

```elixir
# lib/hirehound/scrapers/pnet_scraper.ex
defmodule Hirehound.Scrapers.PNetScraper do
  @moduledoc """
  Scrapes job listings from PNet.
  
  ## Development
  
  Test in IEx first:
      iex> PNetScraper.scrape_page("https://www.pnet.co.za/jobs")
  """
  
  def scrape_page(url) do
    # Copy the working code from IEx
    with {:ok, response} <- Req.get(url),
         {:ok, doc} <- Floki.parse_document(response.body) do
      jobs = extract_jobs(doc)
      {:ok, jobs}
    end
  end
  
  defp extract_jobs(doc) do
    doc
    |> Floki.find(".job-result-card")
    |> Enum.map(&parse_job_card/1)
  end
  
  defp parse_job_card(html) do
    %{
      title: Floki.find(html, ".job-title") |> Floki.text(),
      company: Floki.find(html, ".company-name") |> Floki.text(),
      # ... etc
    }
  end
end
```

### Phase 3: Manual Testing in IEx (Again)

Test your new module:

```elixir
# Recompile and test
iex> recompile()
iex> alias Hirehound.Scrapers.PNetScraper
iex> {:ok, jobs} = PNetScraper.scrape_page("https://www.pnet.co.za/jobs")
iex> jobs |> List.first() |> IO.inspect()
```

### Phase 4: Write Tests

Now that it works manually, write tests:

```elixir
# test/hirehound/scrapers/pnet_scraper_test.exs
defmodule Hirehound.Scrapers.PNetScraperTest do
  use ExUnit.Case
  use ExVCR.Mock, adapter: ExVCR.Adapter.Finch
  
  alias Hirehound.Scrapers.PNetScraper
  
  test "scrapes job listings from PNet" do
    use_cassette "pnet_jobs_page" do
      assert {:ok, jobs} = PNetScraper.scrape_page("https://www.pnet.co.za/jobs")
      assert length(jobs) > 0
      
      first_job = List.first(jobs)
      assert first_job.title
      assert first_job.company
    end
  end
end
```

### Phase 5: Automate

Only after manual testing works, add automation:

```elixir
# lib/hirehound/workers/pnet_scraping_worker.ex
defmodule Hirehound.Workers.PNetScrapingWorker do
  use Oban.Worker, queue: :scraping
  
  alias Hirehound.Scrapers.PNetScraper
  
  @impl Oban.Worker
  def perform(%Job{}) do
    # Now we're confident this works
    PNetScraper.scrape_page("https://www.pnet.co.za/jobs")
  end
end

# Schedule it
Hirehound.Workers.PNetScrapingWorker.new(%{})
|> Oban.insert()
```

---

## Behaviour-Based Architecture

### Behaviours vs Protocols (Clarification)

**Behaviours** (what we use for JobBoard):
- **Module-based polymorphism** - different modules, same interface
- Define with `@callback`, implement with `@behaviour`
- Example: Different scrapers (PNet, LinkedIn) implement same functions
- Compile-time contract verification

**Protocols** (different concept):
- **Data-type polymorphism** - same function, different data types
- Define with `defprotocol`, implement with `defimpl`
- Example: `Enum.map` works on lists, maps, ranges
- Runtime dispatch based on data type

**For Hirehound scrapers:** We use **behaviours** because we have different modules (scrapers) implementing the same interface.

### Why "Scrapers.Behaviour"

**Important naming decision:**

We use `Hirehound.Scrapers.Behaviour` because:

1. **Scope-specific:** This behaviour is **only for scraping** (reading data)
2. **Future-proof:** Leaves room for other job board interactions:
   - `Hirehound.Publishers.Behaviour` - Posting jobs TO boards
   - `Hirehound.Sync.Behaviour` - Bidirectional syncing
   - `Hirehound.Analytics.Behaviour` - Tracking/reporting
3. **Namespace clarity:** Already in `Scrapers` module, so context is obvious
4. **Clean separation:** Each concern (scraping, publishing, syncing) gets its own behaviour

```elixir
# Clear - this is for scraping
defmodule Hirehound.Scrapers.Behaviour do
  @callback scrape_listing_page(url) :: {:ok, list()}
end

# Future - this is for publishing
defmodule Hirehound.Publishers.Behaviour do
  @callback post_job(credentials, job) :: {:ok, id}
end

# Future - this is for syncing
defmodule Hirehound.Sync.Behaviour do
  @callback sync_job(credentials, job) :: :ok
end
```

### Defining the Scraper Behaviour

Create behaviours for extensibility and polymorphism:

```elixir
# lib/hirehound/scrapers/behaviour.ex
defmodule Hirehound.Scrapers.Behaviour do
  @moduledoc """
  Behaviour for job board scrapers.
  
  Each job board (PNet, LinkedIn, CareerJunction) implements this behaviour.
   
  ## IMPORTANT: Listing Pages vs Detail Pages
  
  Do NOT confuse:
  - **Listing pages** - Show MULTIPLE jobs (e.g., /jobs, /jobs?page=2)
  - **Detail pages** - Show ONE job with full info (e.g., /jobs/12345)
  
  Most scrapers use a two-stage process:
  1. Scrape listing pages to get job URLs/IDs
  2. Scrape detail pages for full job data
  
  ## URL-Based Routing
  
  Scrapers declare which URLs they handle via `url_patterns/0`.
  This enables automatic routing: just call `Scraper.scrape_url(any_url)`
  and the system figures out which scraper to use!
  """
  
  @doc """
  Returns metadata about the job board.
  """
  @callback metadata() :: %{
    name: String.t(),
    base_url: String.t(),
    rate_limit: integer(),
    scraping_frequency: atom(),  # :hourly, :daily, etc.
    requires_detail_page: boolean()  # true if must visit detail page for full data
  }
  
  @doc """
  Returns URL patterns this scraper handles.
  
  Enables auto-routing: `Scraper.scrape_url(url)` uses this to determine
  which scraper to call.
  
  ## Returns
  
  A map with:
  - `domains` - List of domains this scraper handles (without www)
  - `listing_path_pattern` - Regex matching listing page paths
  - `detail_path_pattern` - Regex matching detail page paths
  
  ## Example
  
      def url_patterns do
        %{
          domains: ["pnet.co.za"],
          listing_path_pattern: ~r{^/jobs/?(\?.*)?$},
          detail_path_pattern: ~r{^/jobs/\d+}
        }
      end
  """
  @callback url_patterns() :: %{
    domains: list(String.t()),
    listing_path_pattern: Regex.t(),
    detail_path_pattern: Regex.t()
  }
  
  @doc """
  Scrapes a LISTING PAGE (shows multiple jobs).
  
  Returns list of job summaries, which may include detail page URLs.
  
  Returns `{:ok, [%{title: ..., detail_url: ...}, ...]}` or `{:error, reason}`.
  """
  @callback scrape_listing_page(url :: String.t()) :: 
    {:ok, list(map())} | {:error, term()}
  
  @doc """
  Scrapes a DETAIL PAGE (single job with full information).
  
  Only needed if listing page doesn't have complete data.
  
  Returns `{:ok, %{title: ..., description: ..., requirements: ...}}` or `{:error, reason}`.
  """
  @callback scrape_detail_page(url :: String.t()) :: 
    {:ok, map()} | {:error, term()}
  
  @doc """
  Generates list of LISTING PAGE URLs to scrape for this job board.
  
  These should be pages that show multiple jobs (search results, category pages).
  NOT detail pages for individual jobs.
  """
  @callback generate_listing_urls(opts :: keyword()) :: list(String.t())
  
  @doc """
  Normalizes raw scraped data into our unified schema.
  
  Works for data from either listing or detail pages.
  """
  @callback normalize_job(raw_job :: map()) :: 
    {:ok, map()} | {:error, term()}
  
  @doc """
  Detects if a listing page has more results (pagination).
  """
  @callback has_next_page?(html :: String.t()) :: boolean()
  
  @doc """
  Extracts the next listing page URL from HTML.
  """
  @callback next_page_url(html :: String.t()) :: String.t() | nil
end
```

### Implementing the Behaviour

#### Example 1: Two-Stage Scraping (Listing → Detail)

```elixir
# lib/hirehound/scrapers/pnet_scraper.ex
defmodule Hirehound.Scrapers.PNetScraper do
  @behaviour Hirehound.Scrapers.Behaviour
  
  # @impl ensures we're implementing a callback
  # Compiler will warn if signature doesn't match
  
  @impl true
  def metadata do
    %{
      name: "PNet",
      base_url: "https://www.pnet.co.za",
      rate_limit: 100,  # requests per minute
      scraping_frequency: :hourly,
      requires_detail_page: true  # Must visit detail page for full description
    }
  end
  
  @impl true
  def url_patterns do
    %{
      domains: ["pnet.co.za"],  # Handles pnet.co.za and www.pnet.co.za
      listing_path_pattern: ~r{^/jobs/?(\?.*)?$},  # /jobs or /jobs?category=it&page=2
      detail_path_pattern: ~r{^/jobs/\d+}          # /jobs/12345
    }
  end
  
  @impl true
  def scrape_listing_page(url) do
    # Scrape page that shows MULTIPLE jobs
    with {:ok, response} <- Req.get(url),
         {:ok, doc} <- Floki.parse_document(response.body) do
      
      jobs = 
        doc
        |> Floki.find(".job-result-card")  # Listing page selector
        |> Enum.map(fn card ->
          %{
            title: Floki.find(card, ".job-title") |> Floki.text(),
            company: Floki.find(card, ".company-name") |> Floki.text(),
            location: Floki.find(card, ".location") |> Floki.text(),
            # IMPORTANT: Extract URL to detail page
            detail_url: Floki.find(card, "a.job-link") |> Floki.attribute("href") |> List.first()
          }
        end)
      
      {:ok, jobs}
    end
  end
  
  @impl true
  def scrape_detail_page(url) do
    # Scrape page for ONE specific job with full info
    with {:ok, response} <- Req.get(url),
         {:ok, doc} <- Floki.parse_document(response.body) do
      
      job = %{
        title: Floki.find(doc, "h1.job-title") |> Floki.text(),
        company: Floki.find(doc, ".company-name") |> Floki.text(),
        location: Floki.find(doc, ".job-location") |> Floki.text(),
        # Detail page has full description
        description: Floki.find(doc, ".job-description") |> Floki.raw_html(),
        requirements: Floki.find(doc, ".requirements") |> Floki.raw_html(),
        salary: Floki.find(doc, ".salary") |> Floki.text(),
        posted_date: Floki.find(doc, ".posted-date") |> Floki.text()
      }
      
      {:ok, job}
    end
  end
  
  @impl true
  def generate_listing_urls(opts) do
    # Generate URLs for LISTING PAGES (not detail pages!)
    categories = Keyword.get(opts, :categories, ["it", "engineering"])
    
    Enum.map(categories, fn category ->
      "https://www.pnet.co.za/jobs?category=#{category}"  # Listing page
    end)
  end
  
  @impl true
  def normalize_job(raw_job) do
    # Transform PNet-specific format to our schema
    {:ok, %{
      title: normalize_title(raw_job.title),
      company_name: normalize_company(raw_job.company),
      location: parse_location(raw_job.location),
      description: raw_job.description,
      # ...
    }}
  end
  
  @impl true
  def has_next_page?(html) do
    doc = Floki.parse_document!(html)
    Floki.find(doc, ".pagination .next") != []
  end
  
  @impl true
  def next_page_url(html) do
    doc = Floki.parse_document!(html)
    
    doc
    |> Floki.find(".pagination .next")
    |> Floki.attribute("href")
    |> List.first()
  end
end
```

#### Example 2: Listing-Only Scraping (No Detail Page Needed)

Some job boards include full job information on the listing page itself.

```elixir
# lib/hirehound/scrapers/simple_board_scraper.ex
defmodule Hirehound.Scrapers.SimpleBoardScraper do
  @behaviour Hirehound.Scrapers.Behaviour
  
  @impl true
  def metadata do
    %{
      name: "SimpleJobBoard",
      base_url: "https://www.simplejobs.co.za",
      rate_limit: 50,
      scraping_frequency: :daily,
      requires_detail_page: false  # Listing page has all data!
    }
  end
  
  @impl true
  def scrape_listing_page(url) do
    # Listing page has COMPLETE job information
    with {:ok, response} <- Req.get(url),
         {:ok, doc} <- Floki.parse_document(response.body) do
      
      jobs = 
        doc
        |> Floki.find(".job-card")
        |> Enum.map(fn card ->
          %{
            title: Floki.find(card, ".title") |> Floki.text(),
            company: Floki.find(card, ".company") |> Floki.text(),
            location: Floki.find(card, ".location") |> Floki.text(),
            # Full description available on listing page
            description: Floki.find(card, ".description") |> Floki.raw_html(),
            requirements: Floki.find(card, ".requirements") |> Floki.raw_html(),
            salary: Floki.find(card, ".salary") |> Floki.text(),
            detail_url: nil  # Don't need it!
          }
        end)
      
      {:ok, jobs}
    end
  end
  
  @impl true
  def scrape_detail_page(_url) do
    # Not needed for this job board
    {:error, :not_required}
  end
  
  @impl true
  def generate_listing_urls(_opts) do
    [
      "https://www.simplejobs.co.za/jobs",
      "https://www.simplejobs.co.za/jobs?page=2"
    ]
  end
  
  # ... other callbacks
end
```

#### Orchestrating Two-Stage Scraping

```elixir
defmodule Hirehound.Scrapers.Orchestrator do
  @doc """
  Scrapes a job board using appropriate strategy.
  """
  def scrape_board(scraper_module) do
    metadata = scraper_module.metadata()
    
    scraper_module.generate_listing_urls([])
    |> Enum.flat_map(fn listing_url ->
      # Step 1: Scrape listing page
      {:ok, job_summaries} = scraper_module.scrape_listing_page(listing_url)
      
      if metadata.requires_detail_page do
        # Step 2: Scrape each detail page (if needed)
        Enum.map(job_summaries, fn summary ->
          {:ok, full_job} = scraper_module.scrape_detail_page(summary.detail_url)
          
          # Merge summary + detail data
          Map.merge(summary, full_job)
        end)
      else
        # Listing page had everything we need
        job_summaries
      end
    end)
    |> Enum.map(fn raw_job ->
      # Step 3: Normalize to our schema
      {:ok, normalized} = scraper_module.normalize_job(raw_job)
      normalized
    end)
  end
end
```

---

## URL-Based Auto-Routing Architecture

### The Vision: Just Paste Any URL

Instead of manually selecting which scraper to use, the system **auto-detects** based on the URL:

```elixir
# ❌ OLD WAY: Manual routing
iex> PNetScraper.scrape_listing_page("https://pnet.co.za/jobs")

# ✅ NEW WAY: Auto-routing (also supports old way!)
iex> Scraper.scrape_url("https://pnet.co.za/jobs")
# System detects: "pnet.co.za" → PNetScraper → listing page → scrape
```

**Both patterns work!** Auto-routing is **additive**, not replacing.

### Layered Architecture

```
                                    ┌─────────────────────────────────┐
                                    │  IEx / Production / UI Code     │
                                    └─────────────────────────────────┘
                                              │         │
                                              │         │
                              Direct Call ────┘         └──── Auto-Route
                              (explicit)                     (convenient)
                                    │                           │
                                    │                           ↓
                                    │         ┌─────────────────────────────────┐
                                    │         │  Scraper.scrape_url/1           │
                                    │         │  (Auto-routing wrapper)         │
                                    │         └─────────────────────────────────┘
                                    │                           │
                                    │                           ↓
                                    │         ┌─────────────────────────────────┐
                                    │         │  Registry.lookup(url)           │
                                    │         │  "pnet.co.za" → PNetScraper     │
                                    │         │  "/jobs" → :listing             │
                                    │         └─────────────────────────────────┘
                                    │                           │
                                    └───────────────────────────┘
                                                  │
                                                  ↓
                    ┌─────────────────────────────────────────────────────────┐
                    │         PNetScraper (implements Scrapers.Behaviour)     │
                    ├─────────────────────────────────────────────────────────┤
                    │  - url_patterns()           (domain mapping)            │
                    │  - scrape_listing_page()    (scrapes MULTIPLE jobs)     │
                    │  - scrape_detail_page()     (scrapes ONE job)           │
                    │  - normalize_job()          (to unified schema)         │
                    └─────────────────────────────────────────────────────────┘
```

**Key insight:** Both paths end up calling the same underlying scraper functions!

### Implementation: Scraper Registry

```elixir
# lib/hirehound/scrapers/registry.ex
defmodule Hirehound.Scrapers.Registry do
  @moduledoc """
  Registry that maps URLs to scraper modules.
  
  On startup, builds a lookup table from all scraper URL patterns.
  Used by `Scraper.scrape_url/1` for auto-routing.
  """
  
  use GenServer
  
  # List all scraper modules
  @scrapers [
    Hirehound.Scrapers.PNetScraper,
    Hirehound.Scrapers.LinkedInScraper,
    Hirehound.Scrapers.CareerJunctionScraper
  ]
  
  ## Client API
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  
  @doc """
  Looks up which scraper handles the given URL.
  
  Returns `{:ok, scraper_module, page_type}` or `{:error, reason}`.
  
  ## Examples
  
      iex> Registry.lookup("https://pnet.co.za/jobs")
      {:ok, Hirehound.Scrapers.PNetScraper, :listing}
      
      iex> Registry.lookup("https://pnet.co.za/jobs/12345")
      {:ok, Hirehound.Scrapers.PNetScraper, :detail}
      
      iex> Registry.lookup("https://unknown-site.com/jobs")
      {:error, :unknown_job_board}
  """
  def lookup(url) when is_binary(url) do
    uri = URI.parse(url)
    domain = normalize_domain(uri.host)
    
    GenServer.call(__MODULE__, {:lookup, domain, uri.path})
  end
  
  ## Server Callbacks
  
  @impl true
  def init(_) do
    # Build domain → scraper lookup table
    registry = 
      @scrapers
      |> Enum.flat_map(fn scraper ->
        patterns = scraper.url_patterns()
        
        Enum.map(patterns.domains, fn domain ->
          {normalize_domain(domain), scraper}
        end)
      end)
      |> Map.new()
    
    {:ok, registry}
  end
  
  @impl true
  def handle_call({:lookup, domain, path}, _from, registry) do
    case Map.get(registry, domain) do
      nil -> 
        {:reply, {:error, :unknown_job_board}, registry}
      
      scraper_module ->
        page_type = detect_page_type(scraper_module, path)
        {:reply, {:ok, scraper_module, page_type}, registry}
    end
  end
  
  ## Private Helpers
  
  defp normalize_domain(nil), do: nil
  defp normalize_domain(domain) do
    domain
    |> String.downcase()
    |> String.replace_prefix("www.", "")
  end
  
  defp detect_page_type(scraper_module, path) do
    patterns = scraper_module.url_patterns()
    
    cond do
      Regex.match?(patterns.detail_path_pattern, path) -> :detail
      Regex.match?(patterns.listing_path_pattern, path) -> :listing
      true -> :unknown
    end
  end
end
```

### Implementation: Unified Scraper Interface

```elixir
# lib/hirehound/scraper.ex
defmodule Hirehound.Scraper do
  @moduledoc """
  Unified interface for scraping any job board URL.
  
  Automatically routes to the correct scraper based on URL.
  
  ## Examples
  
      # Auto-detects PNet listing page
      iex> Scraper.scrape_url("https://pnet.co.za/jobs")
      {:ok, [%{title: "...", ...}, ...]}
      
      # Auto-detects PNet detail page
      iex> Scraper.scrape_url("https://pnet.co.za/jobs/12345")
      {:ok, %{title: "...", description: "...", ...}}
      
      # Auto-detects LinkedIn
      iex> Scraper.scrape_url("https://linkedin.com/jobs/view/98765")
      {:ok, %{...}}
      
      # Debug which scraper would be used
      iex> Scraper.which_scraper("https://pnet.co.za/jobs")
      {:ok, Hirehound.Scrapers.PNetScraper, :listing}
  
  ## Direct Calls Still Work!
  
  You can still call scrapers directly when you know which one to use:
  
      iex> PNetScraper.scrape_listing_page("https://pnet.co.za/jobs")
      {:ok, [...]}
  
  Auto-routing is just a convenience layer on top!
  """
  
  alias Hirehound.Scrapers.Registry
  
  @doc """
  Scrapes any job board URL.
  
  Automatically determines:
  1. Which scraper to use (based on domain)
  2. Whether it's a listing or detail page (based on path pattern)
  3. Which function to call (`scrape_listing_page` or `scrape_detail_page`)
  
  Returns the same result as calling the scraper directly.
  
  ## Examples
  
      # Listing page
      iex> Scraper.scrape_url("https://pnet.co.za/jobs")
      {:ok, [%{title: "Senior Developer", ...}, ...]}
      
      # Detail page
      iex> Scraper.scrape_url("https://pnet.co.za/jobs/12345")
      {:ok, %{title: "Senior Developer", description: "...", ...}}
      
      # Unknown job board
      iex> Scraper.scrape_url("https://unknown-site.com/jobs")
      {:error, "No scraper found for URL: https://unknown-site.com/jobs"}
  """
  def scrape_url(url) when is_binary(url) do
    case Registry.lookup(url) do
      {:ok, scraper_module, :listing} ->
        # Delegate to scraper's listing function
        scraper_module.scrape_listing_page(url)
      
      {:ok, scraper_module, :detail} ->
        # Delegate to scraper's detail function
        scraper_module.scrape_detail_page(url)
      
      {:ok, scraper_module, :unknown} ->
        # Path didn't match patterns - try both
        # (Useful for edge cases or new URL formats)
        case scraper_module.scrape_listing_page(url) do
          {:ok, []} -> scraper_module.scrape_detail_page(url)
          result -> result
        end
      
      {:error, :unknown_job_board} ->
        {:error, "No scraper found for URL: #{url}"}
    end
  end
  
  @doc """
  Returns which scraper would handle this URL (for debugging).
  
  Useful for:
  - Debugging URL pattern matching
  - Validating URLs before scraping
  - Discovering which scraper handles a domain
  
  ## Examples
  
      iex> Scraper.which_scraper("https://pnet.co.za/jobs")
      {:ok, Hirehound.Scrapers.PNetScraper, :listing}
      
      iex> Scraper.which_scraper("https://pnet.co.za/jobs/12345")
      {:ok, Hirehound.Scrapers.PNetScraper, :detail}
      
      iex> Scraper.which_scraper("https://linkedin.com/jobs/view/98765")
      {:ok, Hirehound.Scrapers.LinkedInScraper, :detail}
      
      iex> Scraper.which_scraper("https://unknown.com/jobs")
      {:error, :unknown_job_board}
  """
  def which_scraper(url) when is_binary(url) do
    Registry.lookup(url)
  end
  
  @doc """
  Lists all registered scrapers and their domains.
  
  Useful for seeing what job boards are supported.
  
  ## Example
  
      iex> Scraper.list_scrapers()
      [
        %{
          module: Hirehound.Scrapers.PNetScraper,
          name: "PNet",
          domains: ["pnet.co.za"]
        },
        %{
          module: Hirehound.Scrapers.LinkedInScraper,
          name: "LinkedIn",
          domains: ["linkedin.com"]
        }
      ]
  """
  def list_scrapers do
    # Get all scraper modules from Registry
    Application.get_env(:hirehound, :scrapers, [])
    |> Enum.map(fn scraper ->
      metadata = scraper.metadata()
      patterns = scraper.url_patterns()
      
      %{
        module: scraper,
        name: metadata.name,
        domains: patterns.domains
      }
    end)
  end
end
```

### Adding to Supervision Tree

```elixir
# lib/hirehound/application.ex
defmodule Hirehound.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      Hirehound.Repo,
      # Add Registry to supervision tree
      Hirehound.Scrapers.Registry,
      # ... other workers
    ]
    
    opts = [strategy: :one_for_one, name: Hirehound.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Usage: Both Patterns Work

#### Pattern 1: Direct Calls (Explicit)

**When to use:**
- ✅ In production code where you know the scraper
- ✅ In tests (explicit, no magic)
- ✅ When you want specific scraper behavior
- ✅ For performance (no lookup overhead)
- ✅ When debugging specific scraper logic

```elixir
# Production worker - explicit and clear
defmodule Hirehound.Workers.ScrapingWorker do
  def perform(%{args: %{"source" => "pnet", "url" => url}}) do
    # Direct call - no ambiguity
    PNetScraper.scrape_listing_page(url)
  end
end

# Tests - explicit about what you're testing
test "PNet scraper handles pagination" do
  use_cassette "pnet_jobs_page_2" do
    assert {:ok, jobs} = PNetScraper.scrape_listing_page(url)
    assert length(jobs) == 20
  end
end

# IEx - when you know exactly what you want
iex> alias Hirehound.Scrapers.PNetScraper
iex> PNetScraper.scrape_listing_page("https://pnet.co.za/jobs")
{:ok, [...]}
```

#### Pattern 2: Auto-Routing (Convenient)

**When to use:**
- ✅ In IEx exploration (just paste URLs!)
- ✅ When building "paste any job URL" UI features
- ✅ When crawling/discovering URLs (don't know source upfront)
- ✅ For quick prototyping
- ✅ When source is dynamic (user input, discovered links)

```elixir
# IEx exploration - just paste any URL!
iex> Scraper.scrape_url("https://pnet.co.za/jobs")
{:ok, [...]}

iex> Scraper.scrape_url("https://linkedin.com/jobs/view/12345")
{:ok, %{...}}

# UI feature - "Import job from URL"
def import_job_from_url(user_provided_url) do
  # Don't know which scraper - let system figure it out
  case Scraper.scrape_url(user_provided_url) do
    {:ok, job_data} -> 
      Jobs.create_posting(job_data)
    
    {:error, reason} ->
      {:error, "Could not scrape URL: #{reason}"}
  end
end

# Crawling - following discovered links
def follow_links(html, base_url) do
  html
  |> extract_job_urls()
  |> Enum.map(fn url ->
    # Auto-routes to correct scraper!
    Scraper.scrape_url(url)
  end)
end

# Debugging - which scraper handles this?
iex> Scraper.which_scraper("https://some-new-site.com/jobs/123")
{:error, :unknown_job_board}  # Not supported yet

iex> Scraper.which_scraper("https://pnet.co.za/jobs")
{:ok, Hirehound.Scrapers.PNetScraper, :listing}  # ✓
```

### IEx Workflow with Auto-Routing

```elixir
# Start app
$ iex -S mix

# Just paste ANY URL you find!
iex> Scraper.scrape_url("https://pnet.co.za/jobs")
{:ok, [%{title: "Senior Dev", ...}, ...]}

# Try a detail page
iex> Scraper.scrape_url("https://pnet.co.za/jobs/12345")
{:ok, %{title: "Senior Dev", description: "...", ...}}

# Try different job board
iex> Scraper.scrape_url("https://linkedin.com/jobs/search?q=developer")
{:ok, [...]}

# Check which scraper would handle it
iex> Scraper.which_scraper("https://pnet.co.za/jobs/abc123")
{:ok, Hirehound.Scrapers.PNetScraper, :detail}

# Still works the old way too!
iex> alias Hirehound.Scrapers.PNetScraper
iex> PNetScraper.scrape_listing_page("https://pnet.co.za/jobs")
{:ok, [...]}

# List all supported job boards
iex> Scraper.list_scrapers()
[
  %{module: PNetScraper, name: "PNet", domains: ["pnet.co.za"]},
  %{module: LinkedInScraper, name: "LinkedIn", domains: ["linkedin.com"]},
  ...
]
```

### Testing Both Patterns

```elixir
# test/hirehound/scrapers/pnet_scraper_test.exs
defmodule Hirehound.Scrapers.PNetScraperTest do
  use Hirehound.DataCase
  use ExVCR.Mock, adapter: ExVCR.Adapter.Finch
  
  alias Hirehound.Scrapers.PNetScraper
  
  describe "scrape_listing_page/1 (direct call)" do
    test "extracts job titles from listing page" do
      use_cassette "pnet_listing_page" do
        url = "https://pnet.co.za/jobs"
        
        assert {:ok, jobs} = PNetScraper.scrape_listing_page(url)
        assert length(jobs) > 0
        assert Enum.all?(jobs, & &1.title)
      end
    end
  end
  
  describe "url_patterns/0" do
    test "declares correct domain patterns" do
      patterns = PNetScraper.url_patterns()
      
      assert "pnet.co.za" in patterns.domains
      assert Regex.match?(patterns.listing_path_pattern, "/jobs")
      assert Regex.match?(patterns.listing_path_pattern, "/jobs?page=2")
      assert Regex.match?(patterns.detail_path_pattern, "/jobs/12345")
    end
  end
end

# test/hirehound/scraper_test.exs
defmodule Hirehound.ScraperTest do
  use Hirehound.DataCase
  use ExVCR.Mock, adapter: ExVCR.Adapter.Finch
  
  alias Hirehound.Scraper
  alias Hirehound.Scrapers.PNetScraper
  
  describe "scrape_url/1 (auto-routing)" do
    test "routes PNet listing URLs correctly" do
      use_cassette "pnet_listing_page" do
        url = "https://pnet.co.za/jobs"
        
        assert {:ok, jobs} = Scraper.scrape_url(url)
        assert length(jobs) > 0
      end
    end
    
    test "routes PNet detail URLs correctly" do
      use_cassette "pnet_detail_page" do
        url = "https://pnet.co.za/jobs/12345"
        
        assert {:ok, job} = Scraper.scrape_url(url)
        assert job.title
        assert job.description
      end
    end
    
    test "returns error for unknown job boards" do
      url = "https://unknown-site.com/jobs"
      
      assert {:error, msg} = Scraper.scrape_url(url)
      assert msg =~ "No scraper found"
    end
  end
  
  describe "which_scraper/1" do
    test "identifies correct scraper for PNet URLs" do
      assert {:ok, PNetScraper, :listing} = 
        Scraper.which_scraper("https://pnet.co.za/jobs")
      
      assert {:ok, PNetScraper, :detail} = 
        Scraper.which_scraper("https://pnet.co.za/jobs/12345")
    end
    
    test "handles www prefix" do
      assert {:ok, PNetScraper, :listing} = 
        Scraper.which_scraper("https://www.pnet.co.za/jobs")
    end
    
    test "returns error for unknown domains" do
      assert {:error, :unknown_job_board} = 
        Scraper.which_scraper("https://unknown.com/jobs")
    end
  end
end
```

### Benefits of This Architecture

✅ **Incredible IEx ergonomics** - Just paste any URL and it works!  
✅ **No manual routing** - System figures out which scraper to use  
✅ **Perfect for exploration** - Try any URL instantly in REPL  
✅ **Great for UI features** - "Paste any job URL" import functionality  
✅ **Crawling-friendly** - Discover URLs, system auto-routes them  
✅ **Self-documenting** - `which_scraper/1` shows what would happen  
✅ **Type safety** - Behaviour enforces `url_patterns/0` callback  
✅ **Direct calls still work** - Not replacing anything, just adding convenience  
✅ **Testable** - Can test auto-routing separately from scraper logic  
✅ **Debuggable** - `which_scraper/1` helps debug URL pattern issues

### Trade-offs & Considerations

⚠️ **URL normalization** - Must handle http vs https, www vs non-www, trailing slashes  
⚠️ **Ambiguous paths** - Some URLs might not clearly match listing or detail patterns  
⚠️ **Subdomain complexity** - careers.company.com vs company.com (add both to domains)  
⚠️ **Pattern maintenance** - URL patterns may change when sites redesign  
⚠️ **Startup overhead** - Registry builds lookup table at startup (minimal, but exists)

**Solutions:**
- Normalize domains consistently (remove www, lowercase)
- Add fallback logic for ambiguous paths (try listing first, then detail)
- Document URL patterns in scraper tests
- Use `which_scraper/1` to debug pattern matching issues

### Real-World Example: Building PNet Scraper

Here's the complete journey from IEx exploration to auto-routing:

```elixir
# ========================================
# STEP 1: Explore in IEx (no code yet!)
# ========================================
$ iex -S mix

# Try auto-routing first (even before implementing!)
iex> Scraper.which_scraper("https://pnet.co.za/jobs")
{:error, :unknown_job_board}  # Not implemented yet

# Manually fetch and explore
iex> url = "https://pnet.co.za/jobs"
iex> {:ok, response} = Req.get(url)
iex> html = response.body

# Check: Is this listing or detail page?
iex> doc = Floki.parse_document!(html)
iex> job_cards = Floki.find(doc, ".job-result-card")
iex> length(job_cards)
25  # ✓ It's a listing page (multiple jobs)

# Extract first job
iex> first_job = List.first(job_cards)
iex> title = Floki.find(first_job, ".job-title") |> Floki.text()
"Senior Developer"  # ✓ Works!

# Get detail URL
iex> detail_url = Floki.find(first_job, "a") |> Floki.attribute("href") |> List.first()
"/jobs/12345"

# ========================================
# STEP 2: Create the scraper module
# ========================================

# lib/hirehound/scrapers/pnet_scraper.ex
defmodule Hirehound.Scrapers.PNetScraper do
  @behaviour Hirehound.Scrapers.Behaviour
  
  @impl true
  def metadata do
    %{
      name: "PNet",
      base_url: "https://www.pnet.co.za",
      rate_limit: 100,
      scraping_frequency: :hourly,
      requires_detail_page: true
    }
  end
  
  @impl true
  def url_patterns do
    %{
      domains: ["pnet.co.za"],
      listing_path_pattern: ~r{^/jobs/?(\?.*)?$},
      detail_path_pattern: ~r{^/jobs/\d+}
    }
  end
  
  @impl true
  def scrape_listing_page(url) do
    # Copy the working code from IEx
    with {:ok, response} <- Req.get(url),
         {:ok, doc} <- Floki.parse_document(response.body) do
      
      jobs = 
        doc
        |> Floki.find(".job-result-card")
        |> Enum.map(&parse_job_card/1)
      
      {:ok, jobs}
    end
  end
  
  defp parse_job_card(card) do
    %{
      title: Floki.find(card, ".job-title") |> Floki.text(),
      company: Floki.find(card, ".company") |> Floki.text(),
      location: Floki.find(card, ".location") |> Floki.text(),
      detail_url: Floki.find(card, "a") |> Floki.attribute("href") |> List.first()
    }
  end
  
  # ... implement other callbacks
end

# ========================================
# STEP 3: Test manually in IEx
# ========================================
$ iex -S mix

# Test direct call
iex> recompile()
iex> alias Hirehound.Scrapers.PNetScraper
iex> {:ok, jobs} = PNetScraper.scrape_listing_page("https://pnet.co.za/jobs")
{:ok, [%{title: "Senior Developer", ...}, ...]}  # ✓ Works!

# Test auto-routing (now works because we added url_patterns!)
iex> alias Hirehound.Scraper
iex> Scraper.which_scraper("https://pnet.co.za/jobs")
{:ok, Hirehound.Scrapers.PNetScraper, :listing}  # ✓ Detected!

iex> Scraper.scrape_url("https://pnet.co.za/jobs")
{:ok, [%{title: "Senior Developer", ...}, ...]}  # ✓ Auto-routed and worked!

# ========================================
# STEP 4: Write tests
# ========================================

# test/hirehound/scrapers/pnet_scraper_test.exs
defmodule Hirehound.Scrapers.PNetScraperTest do
  use Hirehound.DataCase
  use ExVCR.Mock
  
  alias Hirehound.Scrapers.PNetScraper
  alias Hirehound.Scraper
  
  test "direct call: scrape_listing_page/1" do
    use_cassette "pnet_listing" do
      {:ok, jobs} = PNetScraper.scrape_listing_page("https://pnet.co.za/jobs")
      assert length(jobs) > 0
    end
  end
  
  test "auto-routing: Scraper.scrape_url/1" do
    use_cassette "pnet_listing" do
      {:ok, jobs} = Scraper.scrape_url("https://pnet.co.za/jobs")
      assert length(jobs) > 0
    end
  end
  
  test "url pattern detection" do
    assert {:ok, PNetScraper, :listing} = 
      Scraper.which_scraper("https://pnet.co.za/jobs")
    
    assert {:ok, PNetScraper, :detail} = 
      Scraper.which_scraper("https://pnet.co.za/jobs/12345")
  end
end

# ========================================
# STEP 5: Use it anywhere!
# ========================================

# Production - explicit
defmodule ScrapingWorker do
  def perform(%{args: %{"url" => url}}) do
    PNetScraper.scrape_listing_page(url)
  end
end

# UI - auto-routing
def handle_event("import_url", %{"url" => url}, socket) do
  case Scraper.scrape_url(url) do
    {:ok, jobs} -> {:noreply, assign(socket, :jobs, jobs)}
    {:error, _} -> {:noreply, put_flash(socket, :error, "Invalid URL")}
  end
end

# IEx - both work!
iex> PNetScraper.scrape_listing_page("https://pnet.co.za/jobs")  # Direct
iex> Scraper.scrape_url("https://pnet.co.za/jobs")               # Auto
```

**Result:** Maximum flexibility! Use direct calls when you want control, auto-routing when you want convenience.

---

### Using Behaviours Polymorphically

Now you can work with any job board generically (each module implements the same behaviour):

```elixir
defmodule Hirehound.Scrapers.Orchestrator do
  @scrapers [
    Hirehound.Scrapers.PNetScraper,
    Hirehound.Scrapers.LinkedInScraper,
    Hirehound.Scrapers.CareerJunctionScraper
  ]
  
  def scrape_all_boards do
    Enum.map(@scrapers, fn scraper ->
      metadata = scraper.metadata()
      urls = scraper.generate_urls([])
      
      Enum.map(urls, fn url ->
        {:ok, jobs} = scraper.scrape_page(url)
        
        Enum.map(jobs, fn raw_job ->
          {:ok, normalized} = scraper.normalize_job(raw_job)
          # Save to database...
        end)
      end)
    end)
  end
end
```

---

## Step-by-Step Feature Development

### Example: Building Organization Matching

**Step 1: IEx Exploration**

```elixir
# Start with raw data
iex> raw_job = %{company: "Google (Pty) Ltd"}

# Try normalization approaches
iex> name = raw_job.company
iex> normalized = name |> String.downcase() |> String.replace(~r/\(pty\) ltd/, "")
"google"

# Test against existing orgs
iex> alias Hirehound.Organizations
iex> Organizations.find_by_name("google")
# Nil - not found, need fuzzy search

# Try fuzzy matching
iex> String.jaro_distance("google", "Google South Africa")
0.7647058823529411  # Not very similar

iex> String.jaro_distance("google", "Google")
1.0  # Perfect match!
```

**Step 2: Create Helper Functions**

```elixir
# lib/hirehound/organizations/name_matcher.ex
defmodule Hirehound.Organizations.NameMatcher do
  def normalize(name) do
    name
    |> String.downcase()
    |> remove_legal_entities()
    |> String.trim()
  end
  
  defp remove_legal_entities(name) do
    # Logic we tested in IEx
  end
  
  def find_match(name) do
    normalized = normalize(name)
    
    # Try exact match first
    case Organizations.find_by_normalized_name(normalized) do
      nil -> fuzzy_search(normalized)
      org -> {:ok, org}
    end
  end
end
```

**Step 3: Test Manually**

```elixir
iex> recompile()
iex> alias Hirehound.Organizations.NameMatcher
iex> NameMatcher.normalize("Google (Pty) Ltd")
"google"

iex> NameMatcher.find_match("Google (Pty) Ltd")
{:ok, %Organization{name: "Google", ...}}
```

**Step 4: Write Tests**

```elixir
test "normalizes company names" do
  assert NameMatcher.normalize("Google (Pty) Ltd") == "google"
  assert NameMatcher.normalize("ABC Company Limited") == "abc company"
end
```

**Step 5: Integrate into Pipeline**

```elixir
defmodule Hirehound.Jobs.Ingestion do
  def process_raw_job(raw_job) do
    with {:ok, org} <- NameMatcher.find_match(raw_job.company),
         {:ok, job} <- create_job_posting(raw_job, org) do
      {:ok, job}
    end
  end
end
```

---

## IEx Development Tips

### Useful IEx Commands

```elixir
# Recompile after code changes
iex> recompile()

# Import modules for easier access
iex> import Ecto.Query
iex> alias Hirehound.{Jobs, Organizations}

# Run a specific test
iex> ExUnit.run_test("test/hirehound/scrapers/pnet_scraper_test.exs")

# Inspect database state
iex> Repo.all(Organization) |> length()
iex> Repo.get(JobPosting, "some-uuid") |> IO.inspect()

# Time function execution
iex> :timer.tc(fn -> PNetScraper.scrape_page(url) end)
{123456, {:ok, [...]}}  # microseconds, result

# Get help
iex> h Enum.map
iex> i some_variable  # inspect type/value
```

### .iex.exs Configuration

Create `.iex.exs` in project root for automatic imports:

```elixir
# .iex.exs
import Ecto.Query
alias Hirehound.Repo
alias Hirehound.{Jobs, Organizations, Scraper}
alias Hirehound.Jobs.JobPosting
alias Hirehound.Organizations.Organization

# Import specific scrapers for direct use
alias Hirehound.Scrapers.{
  PNetScraper,
  LinkedInScraper,
  CareerJunctionScraper
}

# Helper functions
defmodule H do
  @doc """
  Quick scrape using auto-routing.
  Just paste any job board URL!
  """
  def scrape(url) do
    Scraper.scrape_url(url)
  end
  
  @doc "Check which scraper handles a URL"
  def which(url) do
    Scraper.which_scraper(url)
  end
  
  @doc "List all supported job boards"
  def scrapers do
    Scraper.list_scrapers()
  end
  
  @doc "Quick PNet scrape (direct call)"
  def pnet do
    PNetScraper.scrape_listing_page("https://www.pnet.co.za/jobs")
  end
  
  @doc "Reset database (dev only!)"
  def reset_db do
    # Careful! Only in dev
    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE job_postings CASCADE")
  end
end

IO.puts """

Hirehound IEx loaded! 🐕

Quick commands:
  H.scrape(url)     - Auto-scrape any URL
  H.which(url)      - Check which scraper handles URL
  H.scrapers()      - List all scrapers
  H.pnet()          - Quick PNet scrape
  
Examples:
  iex> H.scrape("https://pnet.co.za/jobs")
  iex> H.which("https://pnet.co.za/jobs/12345")
  iex> PNetScraper.scrape_listing_page("https://pnet.co.za/jobs")
"""
```

Now when you start IEx, everything is pre-loaded with helpful commands:

```elixir
$ iex -S mix
Hirehound IEx loaded! 🐕

Quick commands:
  H.scrape(url)     - Auto-scrape any URL
  H.which(url)      - Check which scraper handles URL
  ...

# Auto-routing - super quick!
iex> H.scrape("https://pnet.co.za/jobs")
{:ok, [...]}

# Or use direct calls when you want control
iex> PNetScraper.scrape_listing_page("https://pnet.co.za/jobs")
{:ok, [...]}
```

---

## Code Organization Patterns

### Namespace by Domain

```
lib/hirehound/
├── scrapers/           # Everything scraping-related
│   ├── behaviours/
│   │   └── job_board_behaviour.ex
│   ├── pnet_scraper.ex
│   ├── linkedin_scraper.ex
│   └── orchestrator.ex
├── jobs/               # Job posting domain
│   ├── job_posting.ex  # Schema
│   ├── ingestion.ex    # Processing pipeline
│   └── queries.ex      # Ecto queries
├── organizations/      # Organization domain
│   ├── organization.ex
│   ├── name_matcher.ex
│   └── enrichment.ex
├── deduplication/      # Deduplication logic
│   ├── job_matcher.ex
│   └── org_matcher.ex
└── workers/            # Background jobs
    ├── scraping_worker.ex
    └── deduplication_worker.ex
```

### Separation of Concerns

```elixir
# ✅ GOOD: Separate data, logic, and side effects

# Data structure (pure)
defmodule Hirehound.Jobs.JobPosting do
  use Ecto.Schema
  # Just schema definition, no business logic
end

# Business logic (pure functions)
defmodule Hirehound.Jobs.Processing do
  def normalize(raw_job), do: ...
  def validate(job), do: ...
end

# Side effects (database, HTTP, etc.)
defmodule Hirehound.Jobs do
  def create_posting(attrs) do
    attrs
    |> Processing.normalize()
    |> Processing.validate()
    |> insert_to_db()
  end
end

# ❌ AVOID: Mixing concerns
defmodule JobPosting do
  use Ecto.Schema
  
  def scrape_and_save(url) do  # Too many responsibilities!
    # HTTP call (side effect)
    # Parsing (logic)
    # Validation (logic)
    # Database (side effect)
  end
end
```

---

## Testing Philosophy

### Test Pyramid

1. **Unit tests** (70%) - Pure functions, no I/O
2. **Integration tests** (20%) - Database, modules working together
3. **End-to-end tests** (10%) - Full workflows

### Testing Scrapers

```elixir
# Use ExVCR for deterministic tests
test "scrapes PNet job listings" do
  use_cassette "pnet_jobs_first_page" do
    assert {:ok, jobs} = PNetScraper.scrape_page("https://www.pnet.co.za/jobs")
    
    assert length(jobs) > 0
    
    first_job = List.first(jobs)
    assert first_job.title
    assert first_job.company
    assert first_job.location
  end
end

# Record the cassette once:
# 1. Run test with MIX_ENV=test mix test (it will hit real URL)
# 2. ExVCR saves response to fixture/vcr_cassettes/
# 3. Subsequent runs use cached response
```

---

## Migration Strategy

### Database Migrations - Incremental

```elixir
# ✅ GOOD: Small, focused migrations
defmodule Hirehound.Repo.Migrations.CreateJobPostings do
  use Ecto.Migration
  
  def change do
    create table(:job_postings, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :title, :string, null: false
      add :description, :text
      
      timestamps()
    end
  end
end

# Then in separate migration, add more fields
defmodule Hirehound.Repo.Migrations.AddJobPostingMetadata do
  use Ecto.Migration
  
  def change do
    alter table(:job_postings) do
      add :source_name, :string
      add :source_url, :string
      add :scraped_at, :utc_datetime
    end
  end
end
```

**Test in IEx:**

```elixir
# Run migration
iex> Mix.Task.run("ecto.migrate")

# Verify schema
iex> Hirehound.Repo.query!("SELECT column_name FROM information_schema.columns WHERE table_name = 'job_postings'")

# Test creating record
iex> %JobPosting{title: "Test"} |> Repo.insert()
```

---

## Summary: The Hirehound Way

### Development Workflow

1. **Start in IEx** - Explore, experiment, validate
2. **Codify** - Move working code into modules
3. **Test manually** - Verify in IEx again
4. **Write tests** - Lock in behavior
5. **Automate** - Add to workers/cron only after confidence
6. **Use behaviours** - Define module contracts for extensibility
7. **Prefer Req, Oban** - Modern Elixir libraries (NOT Jido for now)
8. **Iterate** - Small steps, continuous validation

### Architecture Patterns

**Layered Design:**
- ✅ **Layer 1:** Direct scraper calls (`PNetScraper.scrape_listing_page(url)`)
  - Use in production, tests, when you know the scraper
  - Explicit, fast, clear
  
- ✅ **Layer 2:** Auto-routing (`Scraper.scrape_url(url)`)
  - Use in IEx, UI features, crawling
  - Convenient, exploratory
  - Just a thin routing layer - calls Layer 1 internally

**Both patterns coexist!** Auto-routing is additive, not replacing direct calls.

### Two Ways to Scrape

```elixir
# ✅ Direct call (when you know the scraper)
iex> PNetScraper.scrape_listing_page("https://pnet.co.za/jobs")

# ✅ Auto-routing (when you just have a URL)
iex> Scraper.scrape_url("https://pnet.co.za/jobs")
# Internally calls: PNetScraper.scrape_listing_page(url)
```

**Use the right tool for the job:**
- Production code → Direct calls
- IEx exploration → Auto-routing
- Tests → Direct calls (explicit)
- User input → Auto-routing (don't know source)
- Crawling → Auto-routing (discovered URLs)

### Quick Reference: When to Use Which Pattern

| Scenario | Use | Example |
|----------|-----|---------|
| **IEx exploration** | `Scraper.scrape_url(url)` | `H.scrape("https://pnet.co.za/jobs")` |
| **Production workers** | `PNetScraper.scrape_listing_page(url)` | Explicit, clear which scraper |
| **Unit tests** | `PNetScraper.scrape_listing_page(url)` | Test specific scraper logic |
| **Integration tests** | `Scraper.scrape_url(url)` | Test full routing system |
| **User pastes URL in UI** | `Scraper.scrape_url(url)` | Don't know which board |
| **Following discovered links** | `Scraper.scrape_url(url)` | URLs found while crawling |
| **Scheduled scraping** | `PNetScraper.scrape_listing_page(url)` | Know the board/URL upfront |
| **Debugging scraper** | `PNetScraper.scrape_listing_page(url)` | Isolate specific scraper |
| **Debugging routing** | `Scraper.which_scraper(url)` | Check pattern matching |
| **Quick prototype** | `Scraper.scrape_url(url)` | Fastest in IEx |

---

## Common Pitfalls to Avoid

### ❌ PITFALL #1: Confusing Listing Pages with Detail Pages

**Problem:** Using selectors meant for a listing page on a detail page (or vice versa).

```elixir
# ❌ WRONG: Using listing page selector on detail page
detail_url = "https://www.pnet.co.za/jobs/12345"
{:ok, response} = Req.get(detail_url)
doc = Floki.parse_document!(response.body)

# This won't work! Detail pages don't have .job-result-card
jobs = Floki.find(doc, ".job-result-card")  # Returns []

# ✅ CORRECT: Use appropriate selectors for each page type
defmodule PNetScraper do
  def scrape_listing_page(url) do
    # Listing page shows MULTIPLE jobs
    Floki.find(doc, ".job-result-card")  # ✓
  end
  
  def scrape_detail_page(url) do
    # Detail page shows ONE job
    Floki.find(doc, ".job-details-container")  # ✓
  end
end
```

**How to avoid:**
1. Always check URL pattern first (does it have an ID?)
2. Manually inspect the page in browser
3. Test selectors in IEx before writing code
4. Name functions clearly: `scrape_listing_page` vs `scrape_detail_page`

### ❌ PITFALL #2: Scraping Detail Pages When Listing Has All Data

**Problem:** Making unnecessary HTTP requests when listing page has complete info.

```elixir
# ❌ INEFFICIENT: Visiting detail page when not needed
def scrape_all_jobs do
  {:ok, summaries} = scrape_listing_page(url)
  
  # Unnecessary if listing has full description!
  Enum.map(summaries, fn summary ->
    scrape_detail_page(summary.detail_url)  # Extra HTTP call
  end)
end

# ✅ EFFICIENT: Check metadata first
def scrape_all_jobs(scraper_module) do
  metadata = scraper_module.metadata()
  {:ok, summaries} = scraper_module.scrape_listing_page(url)
  
  if metadata.requires_detail_page do
    # Only scrape detail pages if needed
    Enum.map(summaries, &scraper_module.scrape_detail_page(&1.detail_url))
  else
    summaries  # Listing page had everything
  end
end
```

### ❌ PITFALL #3: Hardcoding URLs Instead of Using URL Patterns

**Problem:** Scraping only one page instead of paginating through all results.

```elixir
# ❌ WRONG: Only scrapes first page
def scrape_jobs do
  scrape_listing_page("https://www.pnet.co.za/jobs")  # Only page 1!
end

# ✅ CORRECT: Generate all listing URLs
def scrape_all_jobs do
  1..10
  |> Enum.map(fn page ->
    "https://www.pnet.co.za/jobs?page=#{page}"  # All pages
  end)
  |> Enum.flat_map(&scrape_listing_page/1)
end
```

---

## Quick Reference: Listing vs Detail Pages

| Aspect | Listing Page | Detail Page |
|--------|--------------|-------------|
| **Shows** | Multiple jobs (10-50) | One job |
| **URL Pattern** | `/jobs`, `/jobs?category=it` | `/jobs/12345`, `/jobs/senior-dev` |
| **Contains** | Summary info | Full information |
| **Typical Fields** | Title, company, location | + Description, requirements, salary |
| **Selector Example** | `.job-result-card` | `.job-details-container` |
| **Pagination** | Yes (page 1, 2, 3...) | No |
| **Function Name** | `scrape_listing_page/1` | `scrape_detail_page/1` |
| **Returns** | List of jobs | Single job |

---

**Remember:** If you can't make it work in IEx, it won't work in production. Start there!
