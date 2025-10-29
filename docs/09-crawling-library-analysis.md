# Crawling Library Analysis & Recommendations

## The Question

Should we use a crawling framework (Crawly, Hop) or build our own with Floki + Req?

**Considerations:**
- Already have Scrapers.Behaviour design
- Using Oban for orchestration
- Expected scale: 20k-150k pages/day
- Some sites may need JavaScript rendering
- Want to avoid wasted effort but also avoid premature complexity

---

## Library Comparison

### 1. Floki (HTML Parser Only)

**What it is:**
- Pure HTML parser with CSS selector support
- **No crawling features** - just parsing

**Pros:**
- ✅ Lightweight, focused
- ✅ Excellent CSS selector support
- ✅ Fast (C-based parser option)
- ✅ We need it anyway (all other tools use it)

**Cons:**
- ❌ No crawling logic (pagination, URL tracking, etc.)
- ❌ You build everything else yourself

**Verdict:** Required building block, not a complete solution

---

### 2. Hop (Lightweight Crawling Framework)

**What it is:**
- Tiny framework built on **Req + Floki**
- Provides: depth-limited crawling, URL tracking, extensibility

**Architecture:**
```elixir
Hop.stream(url)
  ├─ Prefetch (validate before fetch)
  ├─ Fetch (HTTP request)
  └─ Next (decide what to crawl next)
```

**Pros:**
- ✅ Simple and minimal (~100-200 LOC)
- ✅ Built on tools we already use (Req, Floki)
- ✅ Extensible at key stages
- ✅ Lazy stream-based (Elixir-idiomatic)
- ✅ Handles pagination and URL tracking
- ✅ Can integrate with our behaviours

**Cons:**
- ⚠️ Basic feature set
- ⚠️ No built-in middleware/pipelines
- ⚠️ No browser rendering support
- ⚠️ Less battle-tested than Crawly

**Fits our design:**
```elixir
# Could wrap Hop in our behaviour
def scrape_listing_page(url) do
  url
  |> Hop.stream(max_depth: 1)
  |> Enum.take(50)
  |> Enum.map(&extract_jobs/1)
end
```

---

### 3. Crawly (Full-Featured Framework)

**What it is:**
- Comprehensive crawling framework (like Scrapy for Python)
- Opinionated architecture with spiders, middlewares, pipelines

**Features:**
- ✅ Browser rendering support (JavaScript execution)
- ✅ Management UI for monitoring
- ✅ Middleware system (filtering, user agents, etc.)
- ✅ Pipeline system (dedup, validation, storage)
- ✅ Distributed crawling support
- ✅ Battle-tested, mature

**Architecture:**
```
Spider
  ↓
[Middlewares] → Request
  ↓
Fetcher (HTTP or Browser)
  ↓
[Middlewares] → Response
  ↓
Spider.parse_item
  ↓
[Pipelines] → Items
  ↓
Storage
```

**Cons:**
- ❌ **Conflicts with our design**
  - Has its own Spider behaviour (vs our Scrapers.Behaviour)
  - Has its own scheduling/orchestration (vs Oban)
  - Has its own pipeline system (vs our workflows)
- ❌ Opinionated architecture doesn't match ours
- ❌ Would need to adapt our design to fit Crawly
- ❌ Heavier weight than needed

**Verdict:** Too opinionated, conflicts with Oban + Scrapers.Behaviour

---

### 4. Headless Browser Options

#### Option A: chrome-remote-interface (Elixir-native)

**What it is:**
- Elixir client for Chrome DevTools Protocol
- Direct communication with Chrome/Chromium

**Pros:**
- ✅ Pure Elixir (no Node.js dependency)
- ✅ Direct control over Chrome

**Cons:**
- ❌ Low-level API (more code to write)
- ❌ Manual handling of waits, navigation, stealth
- ❌ More effort to productionize

#### Option B: NodeJS + Puppeteer (Hybrid)

**What it is:**
- Use `nodejs` Hex package to run Puppeteer from Elixir
- Pattern from svycal/og-image project

**Architecture:**
```elixir
# In application.ex
{NodeJS.Supervisor, path: "priv/js", pool_size: 4}

# JavaScript file: priv/js/scrape-page.js
module.exports = async function(url) {
  const browser = await puppeteer.launch();
  const page = await browser.newPage();
  await page.goto(url, {waitUntil: 'networkidle0'});
  const html = await page.content();
  await browser.close();
  return html;
}

# Elixir code
html = NodeJS.call!("scrape-page", [url], binary: true)
```

**Pros:**
- ✅ High-level Puppeteer API (easier to use)
- ✅ Battle-tested (Puppeteer is industry standard)
- ✅ Process pool supervision via OTP
- ✅ Large community, lots of examples
- ✅ Easy to hire for (JavaScript knowledge common)

**Cons:**
- ⚠️ Requires Node.js in deployment
- ⚠️ More memory (Chrome + Node processes)
- ⚠️ Additional complexity

**Verdict:** Use this if we need headless browsers

---

## Recommendation: Layered Approach

### **Phase 1: Start Simple (Week 1-4)**

Use **Req + Floki + thin wrapper** for 90% of job boards:

```elixir
defmodule Hirehound.Fetcher do
  @moduledoc """
  Fetch HTML from URLs with politeness and retries.
  """
  
  def fetch_html(url, opts \\ []) do
    url
    |> Req.new()
    |> Req.Request.put_header("user-agent", user_agent())
    |> maybe_add_proxy(opts)
    |> Req.get(
        retry: :transient,
        max_retries: 3,
        retry_delay: &backoff/1
      )
    |> case do
      {:ok, %{status: 200, body: html}} -> {:ok, html}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp backoff(n), do: trunc(:math.pow(2, n) * 1000)  # Exponential backoff
  defp user_agent, do: "HirehoundBot/1.0 (+https://hirehound.co.za)"
end

defmodule Hirehound.Scrapers.PNetScraper do
  @behaviour Hirehound.Scrapers.Behaviour
  
  @impl true
  def scrape_listing_page(url) do
    # Fetch HTML
    {:ok, html} = Fetcher.fetch_html(url)
    
    # Parse with Floki (same as before!)
    doc = Floki.parse_document!(html)
    
    jobs = 
      doc
      |> Floki.find(".job-card")
      |> Enum.map(&extract_job/1)
    
    {:ok, jobs}
  end
end
```

**Why this works:**
- ✅ **Clean separation:** Fetcher handles HTTP, scraper handles parsing
- ✅ **Fits our behaviour design** perfectly
- ✅ **Simple to understand and debug**
- ✅ **Good enough for 90% of job boards**
- ✅ **20k-150k pages/day is easily handled**

**Orchestration with Oban:**
```elixir
# Oban worker for listing pages
defmodule Workers.ListingCrawler do
  use Oban.Worker, queue: :scraping
  
  def perform(%{args: %{"url" => url, "board" => "pnet"}}) do
    scraper = PNetScraper
    {:ok, html} = Fetcher.fetch_html(url)
    {:ok, jobs} = scraper.scrape_listing_page(html)
    
    # Enqueue detail page jobs
    Enum.each(jobs, fn job ->
      %{url: job.detail_url, board: "pnet"}
      |> Workers.DetailScraper.new()
      |> Oban.insert()
    end)
    
    # Continue pagination
    if scraper.has_next_page?(html) do
      next_url = scraper.next_page_url(html)
      %{url: next_url, board: "pnet"}
      |> Workers.ListingCrawler.new()
      |> Oban.insert()
    end
  end
end
```

---

### **Phase 2: Add Headless (When Needed)**

**Only for JavaScript-heavy boards** that don't work with Req + Floki.

Use **NodeJS + Puppeteer** pattern:

```elixir
# 1. Add to mix.exs
{:nodejs, "~> 2.0"}

# 2. Add to application.ex supervision tree
{NodeJS.Supervisor, path: Path.join([Application.app_dir(:hirehound), "priv/js"]), pool_size: 4}

# 3. Create priv/js/package.json
{
  "dependencies": {
    "puppeteer": "^21.0.0"
  }
}

# 4. Create priv/js/fetch-rendered.js
const puppeteer = require('puppeteer');

async function fetchRendered(url) {
  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  
  try {
    const page = await browser.newPage();
    
    // Block images/CSS for speed
    await page.setRequestInterception(true);
    page.on('request', (req) => {
      if (['image', 'stylesheet', 'font'].includes(req.resourceType())) {
        req.abort();
      } else {
        req.continue();
      }
    });
    
    await page.goto(url, {waitUntil: 'networkidle0', timeout: 30000});
    const html = await page.content();
    
    return html;
  } finally {
    await browser.close();
  }
}

module.exports = fetchRendered;

# 5. Create HeadlessFetcher in Elixir
defmodule Hirehound.HeadlessFetcher do
  def fetch_html(url, _opts \\ []) do
    html = NodeJS.call!("fetch-rendered", [url], binary: true)
    {:ok, html}
  rescue
    e -> {:error, e}
  end
end

# 6. Configure per job board
defmodule LinkedInScraper do
  @behaviour Hirehound.Scrapers.Behaviour
  
  @impl true
  def metadata do
    %{
      name: "LinkedIn",
      requires_js: true,  # ← Flag for headless
      # ...
    }
  end
  
  @impl true
  def scrape_listing_page(url) do
    # Use headless fetcher for this board
    {:ok, html} = HeadlessFetcher.fetch_html(url)
    
    # Parse same as always with Floki
    doc = Floki.parse_document!(html)
    # ...
  end
end
```

**Fetcher Selection:**
```elixir
defmodule Hirehound.Crawler do
  def fetch_for_scraper(scraper_module, url) do
    metadata = scraper_module.metadata()
    
    fetcher = if metadata[:requires_js] do
      HeadlessFetcher
    else
      HTTPFetcher  # Default: Req + Floki
    end
    
    fetcher.fetch_html(url)
  end
end
```

---

### **Optional Phase 3: Add Hop (If Needed)**

**Only if** you want to avoid writing pagination/URL tracking yourself.

**Integration with our behaviour:**
```elixir
defmodule Hirehound.HopCrawler do
  @doc """
  Crawls listing pages using Hop, but still calls our behaviours.
  """
  def crawl_listings(scraper_module, start_url) do
    Hop.stream(start_url, 
      max_depth: 5,
      next: fn %{html: html} ->
        # Use our behaviour to decide what's next
        if scraper_module.has_next_page?(html) do
          [scraper_module.next_page_url(html)]
        else
          []
        end
      end
    )
    |> Stream.map(fn %{url: url, html: html} ->
      # Call our behaviour for parsing
      {:ok, jobs} = scraper_module.scrape_listing_page(html)
      {url, jobs}
    end)
    |> Enum.take(100)  # Limit pages
  end
end
```

**Trade-off:** Adds dependency but saves ~100 lines of pagination code.

---

## Comparison Matrix

| Feature | Floki + Req | Hop | Crawly | Headless (Puppeteer) |
|---------|-------------|-----|--------|----------------------|
| **What it does** | HTML parsing | Lightweight crawling | Full framework | JS rendering |
| **HTTP fetching** | Via Req | ✅ Built-in (Req) | ✅ Built-in | ✅ Built-in |
| **HTML parsing** | ✅ Floki | ✅ Floki | ✅ Floki | ✅ Returns HTML |
| **Pagination** | ❌ Manual | ✅ Built-in | ✅ Built-in | ❌ Manual |
| **URL tracking** | ❌ Manual | ✅ Built-in | ✅ Built-in | ❌ Manual |
| **Rate limiting** | ⚠️ Via Oban | ⚠️ Via Oban | ✅ Built-in | ⚠️ Via pool size |
| **Middleware** | ❌ No | ❌ No | ✅ Yes | ❌ No |
| **Pipelines** | ❌ No | ❌ No | ✅ Yes | ❌ No |
| **JS rendering** | ❌ No | ❌ No | ✅ Optional | ✅ Native |
| **Fits Scrapers.Behaviour** | ✅ Perfect | ✅ Good | ❌ Conflicts | ✅ Perfect |
| **Fits Oban** | ✅ Perfect | ✅ Good | ⚠️ Overlaps | ✅ Perfect |
| **Complexity** | Low | Low | High | Medium-High |
| **Setup time** | Minutes | Minutes | Hours | 1-2 days |
| **Maintenance** | Low | Low | Medium | Medium |
| **When to use** | Always | Optional helper | Never | JS-heavy sites |

---

## Detailed Analysis

### Why NOT Crawly?

**Architectural conflict:**

```
Crawly's Architecture:
Spider → Crawly Engine → Scheduler → Fetcher → Pipelines → Storage
  ↓
Owns orchestration, scheduling, storage

Our Architecture:
Scrapers.Behaviour → Oban Workers → Workflows → PostgreSQL
  ↓
Oban owns orchestration, we own storage
```

**Problems:**
1. **Duplicate orchestration** - Crawly schedules requests, Oban schedules jobs
2. **Pipeline conflict** - Crawly has pipelines, we have Oban workflows
3. **Storage conflict** - Crawly expects to own storage, we use Ecto
4. **Behaviour mismatch** - Crawly's Spider behaviour ≠ our Scrapers.Behaviour

**Example of conflict:**
```elixir
# Crawly expects this:
defmodule PNetSpider do
  use Crawly.Spider  # ← Conflicts with our behaviour
  
  def init, do: [start_urls: ["..."]]
  
  def parse_item(response, state) do  # ← Different signature
    # Must return items + requests in Crawly format
    %Crawly.ParsedItem{items: [...], requests: [...]}
  end
end

# We already designed this:
defmodule PNetScraper do
  @behaviour Hirehound.Scrapers.Behaviour
  
  def scrape_listing_page(url) do  # ← Our signature
    {:ok, [...]}
  end
end
```

**Verdict:** Don't use Crawly - it fights our architecture.

---

### Why Hop is Optional (But Nice)

**What Hop gives us:**
- URL deduplication (visited tracking)
- Pagination logic
- Depth limiting
- ~100 lines we don't have to write

**What we'd build ourselves anyway:**
- Oban handles orchestration
- Scrapers.Behaviour handles parsing
- Our own Fetcher for rate limiting

**Hop integration example:**
```elixir
defmodule Hirehound.Crawler do
  @doc """
  Optional Hop-based crawler that respects our behaviours.
  """
  def crawl_with_hop(scraper_module, start_url) do
    Hop.stream(start_url,
      max_depth: 3,
      fetch: fn url ->
        # Use our Fetcher
        {:ok, html} = Fetcher.fetch_html(url)
        {:ok, html}
      end,
      next: fn %{html: html} ->
        # Use our behaviour to find next pages
        if scraper_module.has_next_page?(html) do
          [scraper_module.next_page_url(html)]
        else
          []
        end
      end
    )
    |> Stream.map(fn %{html: html} ->
      # Use our behaviour to parse
      scraper_module.scrape_listing_page(html)
    end)
  end
end
```

**Trade-off:**
- **With Hop:** Less code, built-in visited tracking
- **Without Hop:** More control, one less dependency

**Recommendation:** Start without Hop, add later if pagination gets complex.

---

## Headless Browser Decision

### When Do We Need It?

**Only if:**
1. ✅ Site requires JavaScript to load job listings
2. ✅ Anti-bot measures block regular HTTP requests
3. ✅ Content loads via AJAX/XHR with no direct API

**Try first:**
1. Inspect network tab for JSON/XHR endpoints
2. Check if `?no_js=true` or similar parameter exists
3. Try Req with proper headers/cookies

**Most job boards DON'T need headless:**
- PNet: Static HTML ✅
- CareerJunction: Static HTML ✅
- Indeed: Some JS, but has JSON endpoints ✅
- LinkedIn: Heavy JS, might need headless ⚠️

### Headless Choice: NodeJS + Puppeteer

**Why Puppeteer over chrome-remote-interface:**

| Aspect | Puppeteer (via NodeJS) | chrome-remote-interface |
|--------|------------------------|-------------------------|
| **API Level** | High-level, ergonomic | Low-level CDP |
| **Waits/Navigation** | Built-in helpers | Manual implementation |
| **Stealth/Anti-detection** | Good plugins available | Manual |
| **Code to write** | Less | More |
| **Community/Examples** | Huge | Small |
| **Deployment** | Need Node.js | Elixir-only |
| **Reliability** | Battle-tested | Less mature |

**Recommendation:** Use NodeJS + Puppeteer pattern from og-image.

---

## Final Recommendation: Layered Architecture

### Layer 1: HTTP Fetching (Start Here - Week 1)

**Use:** Req + Floki with thin `Fetcher` module

```elixir
# lib/hirehound/fetcher.ex
defmodule Hirehound.Fetcher do
  @behaviour Hirehound.FetcherBehaviour
  
  @impl true
  def fetch_html(url, opts) do
    # Req-based fetching with retries, backoff, headers
  end
end
```

**Covers:** 90% of job boards (static HTML)

**Effort:** 2-4 hours

---

### Layer 2: Headless Support (Add When Needed - Week 3-4)

**Use:** NodeJS + Puppeteer for JS-heavy sites

```elixir
# lib/hirehound/headless_fetcher.ex
defmodule Hirehound.HeadlessFetcher do
  @behaviour Hirehound.FetcherBehaviour
  
  @impl true
  def fetch_html(url, opts) do
    # Calls NodeJS + Puppeteer
    html = NodeJS.call!("fetch-rendered", [url])
    {:ok, html}
  end
end
```

**Configure per scraper:**
```elixir
defmodule LinkedInScraper do
  def metadata do
    %{requires_js: true}  # ← Use headless
  end
end

defmodule PNetScraper do
  def metadata do
    %{requires_js: false}  # ← Use HTTP
  end
end
```

**Covers:** 10% of job boards (JS-heavy)

**Effort:** 1-2 days

---

### Layer 3: Hop Integration (Optional - Month 2-3)

**Use:** Hop for complex pagination across many boards

**Only add if:**
- Pagination logic gets repetitive across 5+ boards
- URL tracking becomes complex
- Depth-limited crawling is needed

**Effort:** 4-6 hours

---

### Layer 4: Crawly (Never)

**Don't use** - conflicts with our architecture.

---

## Migration Path

### Week 1-2: HTTP-Only Scraping
```
✅ Fetcher module (Req + Floki)
✅ PNetScraper (static HTML)
✅ CareerJunctionScraper (static HTML)
✅ Oban workers for orchestration
```

### Week 3-4: Add Headless for 1-2 Boards
```
✅ NodeJS.Supervisor in application.ex
✅ priv/js/fetch-rendered.js (Puppeteer)
✅ HeadlessFetcher module
✅ LinkedInScraper with requires_js: true
```

### Month 2-3: Evaluate Hop
```
⚠️ Optional: Add Hop if pagination is painful
⚠️ Only if we have 5+ boards with complex pagination
```

---

## Answer to Your Core Concern

> "I'm worried... I don't know if we should 'start simple' with just Floki or if that would be a waste of time"

**Start simple is NOT wasted effort. Here's why:**

1. **20k-150k pages/day is SMALL** - easily handled by Req + Floki
   - That's 0.2-5 requests/second sustained
   - No need for complex infrastructure

2. **90% of job boards are static HTML**
   - PNet: ✅ Static
   - CareerJunction: ✅ Static
   - JobMail: ✅ Static
   - Indeed: ✅ Has JSON API

3. **Your behaviour design is framework-agnostic**
   - `scrape_listing_page(url)` works with ANY fetcher
   - Can swap Fetcher implementation without changing scrapers

4. **Premature optimization is real risk**
   - Crawly adds complexity you don't need
   - Headless browsers add ops burden
   - Start with working system, add complexity only when needed

5. **Layered approach means no rework**
   ```elixir
   # Same scraper code, different fetcher:
   def scrape_listing_page(url) do
     html = get_html(url)  # ← Pluggable!
     doc = Floki.parse_document!(html)
     # ... parsing logic unchanged
   end
   ```

**Bottom line:** Start with Req + Floki. Add headless ONLY when you encounter a board that requires it. This is not wasted effort - it's the right way to build.

---

## Summary Decision Matrix

| Concern | Decision | Reasoning |
|---------|----------|-----------|
| **HTML Parsing** | Floki | Required regardless of choice |
| **HTTP Fetching** | Req | Simple, works for 90% of boards |
| **Crawling Framework** | None (DIY) | Hop/Crawly conflict with our design |
| **Headless Browsers** | NodeJS + Puppeteer | When needed, use proven pattern |
| **Start Simple?** | ✅ YES | Not wasted, right approach |
| **Add Hop?** | Later (optional) | Nice-to-have, not required |
| **Add Crawly?** | ❌ Never | Architectural conflict |

---

## Recommended Architecture

```elixir
# Behaviour-based design (unchanged!)
Scrapers.Behaviour
  ├─ url_patterns/0
  ├─ scrape_listing_page/1  ← Takes HTML, returns jobs
  └─ scrape_detail_page/1   ← Takes HTML, returns job

# Pluggable fetchers
FetcherBehaviour
  └─ fetch_html/2 → {:ok, html}

Fetchers:
  ├─ HTTPFetcher (Req + Floki)      ← Start here
  ├─ HeadlessFetcher (Node + Pptr)  ← Add when needed
  └─ (Future: HopFetcher)            ← Optional

# Orchestration (unchanged!)
Oban Workers + Workflows
  ├─ ListingCrawler worker
  ├─ DetailScraper worker
  └─ Workflow: Scrape → Parse → Dedup → Index
```

**Benefits:**
- ✅ Clean separation of concerns
- ✅ Pluggable fetchers (start simple, add complex)
- ✅ Behaviour design unchanged
- ✅ Oban orchestration unchanged
- ✅ Can mix: PNet uses HTTP, LinkedIn uses headless
- ✅ Testable: mock FetcherBehaviour in tests

---
