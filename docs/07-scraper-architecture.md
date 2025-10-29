# Scraper Architecture - Quick Reference

## The Big Idea

**You can scrape any job board URL two ways:**

```elixir
# Way 1: Direct call (when you know the scraper)
iex> PNetScraper.scrape_listing_page("https://pnet.co.za/jobs")

# Way 2: Auto-routing (just paste the URL!)
iex> Scraper.scrape_url("https://pnet.co.za/jobs")
```

**Both work!** Auto-routing just calls the direct method for you.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         YOUR CODE                                   │
│  (IEx, Workers, Tests, UI, etc.)                                    │
└─────────────────────────────────────────────────────────────────────┘
              │                                    │
              │ Direct Call                        │ Auto-Route
              │ (you pick scraper)                 │ (system picks)
              │                                    │
              ↓                                    ↓
┌───────────────────────────┐     ┌────────────────────────────────────┐
│  PNetScraper              │     │  Scraper.scrape_url/1              │
│  .scrape_listing_page()   │     │  (unified interface)               │
│  .scrape_detail_page()    │     └────────────────────────────────────┘
└───────────────────────────┘                      │
              │                                    ↓
              │                     ┌────────────────────────────────────┐
              │                     │  Registry.lookup(url)              │
              │                     │                                    │
              │                     │  Parse URL:                        │
              │                     │  - Domain: "pnet.co.za"            │
              │                     │  - Path: "/jobs"                   │
              │                     │                                    │
              │                     │  Lookup:                           │
              │                     │  - Domain → PNetScraper            │
              │                     │  - Path → :listing                 │
              │                     └────────────────────────────────────┘
              │                                    │
              └────────────────────────────────────┘
                                   │
                                   ↓
              ┌─────────────────────────────────────────────────┐
              │     PNetScraper (Scrapers.Behaviour)            │
              ├─────────────────────────────────────────────────┤
              │  ✓ url_patterns()                               │
              │  ✓ metadata()                                   │
              │  ✓ scrape_listing_page(url)  ← CALLED           │
              │  ✓ scrape_detail_page(url)                      │
              │  ✓ normalize_job(raw)                           │
              │  ✓ has_next_page?(html)                         │
              │  ✓ next_page_url(html)                          │
              └─────────────────────────────────────────────────┘
                                   │
                                   ↓
                            [Actual Scraping]
```

---

## Components

### 1. Scrapers.Behaviour (Contract)

**File:** `lib/hirehound/scrapers/behaviour.ex`

**Purpose:** Define the interface all scrapers must implement

**Why just "Behaviour"?**
- Namespaced under `Scrapers` module - purpose is clear from context
- Specifically for scraping (not publishing or syncing)
- Leaves room for future: `Publishers.Behaviour`, `Sync.Behaviour`

**Key callbacks:**
- `url_patterns/0` - Which URLs this scraper handles
- `scrape_listing_page/1` - Scrape page with MULTIPLE jobs
- `scrape_detail_page/1` - Scrape page with ONE job
- `metadata/0` - Scraper info (name, rate limits)

### 2. Individual Scrapers (Implementations)

**Files:** 
- `lib/hirehound/scrapers/pnet_scraper.ex`
- `lib/hirehound/scrapers/linkedin_scraper.ex`
- `lib/hirehound/scrapers/career_junction_scraper.ex`

**Purpose:** Implement scraping for specific job boards

**Pattern:**
```elixir
defmodule PNetScraper do
  @behaviour Hirehound.Scrapers.Behaviour
  
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
    # Scraping logic for MULTIPLE jobs
  end
  
  @impl true
  def scrape_detail_page(url) do
    # Scraping logic for ONE job
  end
end
```

### 3. Scrapers.Registry (Router)

**File:** `lib/hirehound/scrapers/registry.ex`

**Purpose:** Maps URLs to scraper modules

**How it works:**
1. On startup, reads `url_patterns()` from all scrapers
2. Builds lookup table: `domain → scraper_module`
3. When given URL, returns which scraper handles it

**API:**
```elixir
Registry.lookup("https://pnet.co.za/jobs")
# → {:ok, PNetScraper, :listing}
```

### 4. Scraper (Unified Interface)

**File:** `lib/hirehound/scraper.ex`

**Purpose:** Convenience wrapper for auto-routing

**How it works:**
1. Look up scraper via Registry
2. Detect page type (listing or detail)
3. Call appropriate function

**API:**
```elixir
Scraper.scrape_url(url)         # Auto-scrape
Scraper.which_scraper(url)      # Debug routing
Scraper.list_scrapers()         # List all supported
```

---

## Usage Patterns

### Pattern A: IEx Exploration (Auto-Routing)

**Best for:** Quick testing, pasting random URLs

```elixir
$ iex -S mix

# Just paste any URL!
iex> H.scrape("https://pnet.co.za/jobs")
{:ok, [...]}

# Check which scraper it would use
iex> H.which("https://linkedin.com/jobs/view/123")
{:ok, LinkedInScraper, :detail}
```

### Pattern B: Production Code (Direct Calls)

**Best for:** Reliable, explicit production code

```elixir
defmodule Hirehound.Workers.PNetScrapingWorker do
  use Oban.Worker
  
  @impl Oban.Worker
  def perform(%Job{args: %{"url" => url}}) do
    # Explicit - we know it's PNet
    PNetScraper.scrape_listing_page(url)
  end
end
```

### Pattern C: UI Features (Auto-Routing)

**Best for:** User-provided URLs, dynamic sources

```elixir
def import_from_url(user_url) do
  # User might paste PNet, LinkedIn, or anything
  case Scraper.scrape_url(user_url) do
    {:ok, job_data} -> create_job(job_data)
    {:error, _} -> {:error, "Unsupported URL"}
  end
end
```

### Pattern D: Testing (Direct Calls)

**Best for:** Testing specific scraper logic

```elixir
test "PNet extracts job titles correctly" do
  use_cassette "pnet_listing" do
    # Explicit - testing PNet scraper specifically
    {:ok, jobs} = PNetScraper.scrape_listing_page(url)
    assert Enum.all?(jobs, & &1.title)
  end
end
```

---

## Development Checklist

When adding a new job board scraper:

- [ ] **Step 1:** Explore URLs in browser
  - [ ] Identify listing page URL(s)
  - [ ] Identify detail page URL pattern
  - [ ] Note if listing has full data or needs detail page

- [ ] **Step 2:** Test in IEx
  - [ ] Fetch listing page HTML
  - [ ] Find CSS selectors for job cards
  - [ ] Extract job data manually
  - [ ] Fetch detail page (if needed)
  - [ ] Extract full job data

- [ ] **Step 3:** Create scraper module
  - [ ] Implement `Scrapers.Behaviour`
  - [ ] Add `url_patterns/0` with domain and path patterns
  - [ ] Implement `scrape_listing_page/1`
  - [ ] Implement `scrape_detail_page/1` (if needed)
  - [ ] Implement other required callbacks

- [ ] **Step 4:** Test both patterns
  - [ ] Direct call in IEx: `PNetScraper.scrape_listing_page(url)`
  - [ ] Auto-routing in IEx: `Scraper.scrape_url(url)`
  - [ ] Verify: `Scraper.which_scraper(url)` returns correct module

- [ ] **Step 5:** Write tests
  - [ ] Unit tests for direct calls
  - [ ] Integration tests for auto-routing
  - [ ] Test URL pattern matching

- [ ] **Step 6:** Add to Registry
  - [ ] Add module to `@scrapers` list in `Registry`
  - [ ] Restart app, verify in `Scraper.list_scrapers()`

---

## Example IEx Session

Here's what a typical IEx development session looks like:

```elixir
$ iex -S mix
Hirehound IEx loaded! 🐕

# Explore a new job board
iex> url = "https://newjobboard.co.za/listings"
iex> {:ok, response} = Req.get(url)
iex> html = response.body

# Is it listing or detail page?
iex> doc = Floki.parse_document!(html)
iex> cards = Floki.find(doc, ".job")
iex> length(cards)
15  # ✓ Listing page (multiple jobs)

# Extract data from first job
iex> first = List.first(cards)
iex> title = Floki.find(first, "h2") |> Floki.text()
"Senior Developer"

# Try auto-routing (will fail - not implemented yet)
iex> H.which(url)
{:error, :unknown_job_board}  # Expected!

# ... create the scraper module ...
# ... implement url_patterns, scrape_listing_page, etc ...

# Recompile and test
iex> recompile()
:ok

# Test direct call
iex> alias Hirehound.Scrapers.NewJobBoardScraper
iex> NewJobBoardScraper.scrape_listing_page(url)
{:ok, [...]}  # ✓ Works!

# Test auto-routing
iex> H.which(url)
{:ok, Hirehound.Scrapers.NewJobBoardScraper, :listing}  # ✓ Detected!

iex> H.scrape(url)
{:ok, [...]}  # ✓ Auto-routed!

# Both patterns work - use whichever fits your needs!
```

---

## Summary

**The architecture is layered and additive:**

1. **Base layer:** Individual scrapers (`PNetScraper`, etc.)
   - Implement `Scrapers.Behaviour`
   - Always directly callable
   - Explicit, testable, fast

2. **Routing layer:** Registry + Scraper
   - Maps URLs to scrapers via `url_patterns()`
   - Provides `scrape_url/1` convenience
   - Optional - doesn't replace direct calls

3. **Helper layer:** `.iex.exs` shortcuts
   - `H.scrape(url)` - Quick access in IEx
   - `H.which(url)` - Debug routing
   - Makes exploration fast and fun

**Result:** Best of both worlds - explicit control when needed, auto-magic when convenient!

---

## Future: Other Job Board Behaviours

Our naming strategy leaves room for future job board interactions:

### Scraping (Current)
```elixir
defmodule Hirehound.Scrapers.Behaviour do
  @callback scrape_listing_page(url) :: {:ok, list()}
  @callback scrape_detail_page(url) :: {:ok, map()}
  # ... focused on reading data
end
```

### Publishing (Future)
```elixir
defmodule Hirehound.Publishers.Behaviour do
  @callback post_job(board_credentials, job_posting) :: {:ok, job_id} | {:error, term()}
  @callback update_job(board_credentials, job_id, changes) :: :ok | {:error, term()}
  @callback delete_job(board_credentials, job_id) :: :ok | {:error, term()}
  @callback supports_feature?(feature) :: boolean()
  # ... focused on writing data
end
```

### Syncing (Future)
```elixir
defmodule Hirehound.Sync.Behaviour do
  @callback sync_job(credentials, job_posting) :: {:ok, :created | :updated | :unchanged}
  @callback reconcile_differences(local, remote) :: {:ok, resolution}
  # ... bidirectional sync
end
```

**Each namespace has its own behaviour** - clean separation of concerns!

---
