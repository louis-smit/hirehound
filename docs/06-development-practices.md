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

**Alternatives considered:**
- ❌ GenStage/Flow - Too low-level for our needs
- ❌ Broadway - Overkill for our data volumes
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

### Defining a JobBoard Behaviour

Create behaviours for extensibility and polymorphism:

```elixir
# lib/hirehound/scrapers/job_board_behaviour.ex
defmodule Hirehound.Scrapers.JobBoardBehaviour do
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
  @behaviour Hirehound.Scrapers.JobBoardBehaviour
  
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
  @behaviour Hirehound.Scrapers.JobBoardBehaviour
  
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
alias Hirehound.{Jobs, Organizations, Scrapers}
alias Hirehound.Jobs.JobPosting
alias Hirehound.Organizations.Organization

# Helper functions
defmodule H do
  def scrape_pnet do
    Hirehound.Scrapers.PNetScraper.scrape_page("https://www.pnet.co.za/jobs")
  end
  
  def reset_db do
    # Careful! Only in dev
    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE job_postings CASCADE")
  end
end

IO.puts("Hirehound IEx loaded. Try: H.scrape_pnet()")
```

Now when you start IEx, everything is pre-loaded:

```elixir
$ iex -S mix
Hirehound IEx loaded. Try: H.scrape_pnet()

iex> H.scrape_pnet()
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

1. **Start in IEx** - Explore, experiment, validate
2. **Codify** - Move working code into modules
3. **Test manually** - Verify in IEx again
4. **Write tests** - Lock in behavior
5. **Automate** - Add to workers/cron only after confidence
6. **Use behaviours** - Define module contracts for extensibility
7. **Prefer Req, Jido, Oban** - Modern Elixir libraries
8. **Iterate** - Small steps, continuous validation

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
