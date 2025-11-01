# Scraping-Storage Separation Strategy

## Philosophy

**Core Principle:** Scrapers should be **pure data extractors** that return structured data without side effects. Storage is a separate concern handled by dedicated modules.

**Benefits:**
- ✅ Test scrapers without database
- ✅ IEx exploration without side effects  
- ✅ Dry runs to preview data quality
- ✅ Quality gates before committing to DB
- ✅ Easy to add validation/preview layers later
- ✅ Multiple output formats (JSON, CSV, DB)
- ✅ Clear debugging (see extracted vs saved data)

---

## The Clean Architecture

```
Scraper (Pure)
    ↓ Returns data structure
Normalization (Pure)
    ↓ Returns normalized data
Validation (Pure)
    ↓ Returns validation result
Ingestion (Side Effect)
    ↓ Saves to database
```

**Scrapers never touch the database.** Workers orchestrate the pipeline.

---

## Implementation Pattern

### 1. Scrapers Return Data (Pure Functions)

```elixir
# lib/hirehound/scrapers/pnet_scraper.ex
defmodule Hirehound.Scrapers.PNetScraper do
  @behaviour Hirehound.Scrapers.Behaviour
  
  @moduledoc """
  PNet job board scraper.
  
  All functions are PURE - they extract data and return it.
  NO database operations, NO side effects.
  """
  
  @impl true
  def scrape_listing_page(url) do
    {:ok, html} = Fetcher.fetch_html(url)
    doc = Floki.parse_document!(html)
    
    jobs = 
      doc
      |> Floki.find("article[data-at='job-item']")
      |> Enum.reject(&is_expired?/1)
      |> Enum.map(&extract_job_summary/1)
    
    {:ok, jobs}  # Returns list of data structures
  end
  
  @impl true
  def scrape_detail_page(url) do
    {:ok, html} = Fetcher.fetch_html(url)
    doc = Floki.parse_document!(html)
    
    # Extract all data into plain map - NO DB!
    job_data = %{
      # Source metadata
      source_name: "pnet",
      source_url: url,
      source_id: extract_job_id(url),
      scraped_at: DateTime.utc_now(),
      
      # Core fields
      title: extract_title(doc),
      company_name: extract_company(doc),
      location: extract_location(doc),
      description: extract_description(doc),
      requirements: extract_requirements(doc),
      
      # Optional fields
      salary: extract_salary(doc),
      job_type: extract_job_type(doc),
      posted_date: extract_posted_date(doc),
      closing_date: extract_closing_date(doc),
      
      # Detail page URL (if needed for detail scraping)
      detail_url: nil  # Already on detail page
    }
    
    {:ok, job_data}
  end
  
  # Private: Pure extraction functions
  defp extract_job_summary(job_card) do
    %{
      title: Floki.find(job_card, "[data-at='job-item-title'] .res-ewgtgq") |> Floki.text(),
      company_name: Floki.find(job_card, "[data-at='job-item-company-name'] .res-ewgtgq") |> Floki.text(),
      location: Floki.find(job_card, "[data-at='job-item-location']") |> Floki.text(),
      salary: Floki.find(job_card, "[data-at='job-item-salary-info']") |> Floki.text(),
      detail_url: Floki.find(job_card, "[data-at='job-item-title']") |> Floki.attribute("href") |> List.first(),
      posted_relative: Floki.find(job_card, "[data-at='job-item-timeago']") |> Floki.text(),
      source_name: "pnet",
      scraped_at: DateTime.utc_now()
    }
  end
  
  defp extract_title(doc) do
    doc
    |> Floki.find("h1.job-title")
    |> Floki.text()
    |> String.trim()
  end
  
  defp extract_company(doc) do
    doc
    |> Floki.find(".company-name")
    |> Floki.text()
    |> String.trim()
  end
  
  # ... more extraction functions (all pure)
end
```

**Key Points:**
- Returns plain Elixir maps
- No `Repo.insert`, no `Ecto.Changeset`
- All fields extracted, even if nil
- Metadata included (source, scraped_at)

---

### 2. Normalization (Pure Transformation)

```elixir
# lib/hirehound/jobs/normalization.ex
defmodule Hirehound.Jobs.Normalization do
  @moduledoc """
  Normalizes raw scraped job data into our canonical format.
  
  PURE FUNCTIONS - no database access, no side effects.
  Input: raw map from scraper
  Output: normalized map ready for storage
  """
  
  def normalize(raw_job_data) do
    normalized = %{
      # Required fields
      title: normalize_title(raw_job_data.title),
      company_name_raw: raw_job_data.company_name,  # Keep original
      company_name: normalize_company_name(raw_job_data.company_name),
      description: sanitize_html(raw_job_data.description),
      
      # Location
      location_raw: raw_job_data.location,
      province: parse_province(raw_job_data.location),
      city: parse_city(raw_job_data.location),
      location_type: infer_location_type(raw_job_data),
      
      # Temporal
      posted_date: parse_date(raw_job_data.posted_date, raw_job_data.posted_relative),
      closing_date: parse_date(raw_job_data.closing_date),
      
      # Optional fields (may be nil)
      salary_min: parse_salary_min(raw_job_data.salary),
      salary_max: parse_salary_max(raw_job_data.salary),
      salary_currency: "ZAR",
      job_type: normalize_job_type(raw_job_data.job_type),
      
      # Source tracking
      source_name: raw_job_data.source_name,
      source_url: raw_job_data.source_url,
      source_id: raw_job_data.source_id,
      scraped_at: raw_job_data.scraped_at,
      
      # Store original for reference
      raw_data: raw_job_data
    }
    
    {:ok, normalized}
  end
  
  # Pure normalization functions
  defp normalize_title(title) do
    title
    |> String.trim()
    |> remove_company_from_title()
    |> String.downcase()
    |> String.capitalize()
  end
  
  defp normalize_company_name(name) do
    name
    |> String.trim()
    |> remove_legal_entities()
    |> String.downcase()
  end
  
  defp remove_legal_entities(name) do
    legal_suffixes = ["(pty) ltd", "pty ltd", "ltd", "limited", "inc"]
    
    Enum.reduce(legal_suffixes, name, fn suffix, acc ->
      String.replace(acc, ~r/\s*#{suffix}\s*$/i, "")
    end)
  end
  
  defp parse_province(location) do
    # Map common variations to standard provinces
    cond do
      location =~ ~r/gauteng|jhb|johannesburg|pretoria|sandton/i -> "Gauteng"
      location =~ ~r/western cape|cape town|cpt/i -> "Western Cape"
      location =~ ~r/kwazulu.*natal|durban|dbn/i -> "KwaZulu-Natal"
      # ... other provinces
      true -> nil
    end
  end
  
  defp parse_date(nil), do: nil
  defp parse_date(date_string) do
    # Parse various date formats
    # Return DateTime or nil
  end
  
  defp infer_location_type(job_data) do
    description = String.downcase(job_data.description || "")
    
    cond do
      description =~ ~r/remote|work from home|wfh/ -> :remote
      description =~ ~r/hybrid/ -> :hybrid
      true -> :onsite
    end
  end
end
```

**Key Points:**
- Takes raw data, returns normalized data
- No database queries
- No Ecto changesets yet
- Pure transformations

---

### 3. Validation (Pure Quality Checks)

```elixir
# lib/hirehound/jobs/validation.ex
defmodule Hirehound.Jobs.Validation do
  @moduledoc """
  Validates normalized job data before storage.
  
  PURE FUNCTIONS - returns {:ok, data} or {:error, reasons}
  """
  
  def validate(normalized_data) do
    with :ok <- validate_required_fields(normalized_data),
         :ok <- validate_company_name(normalized_data),
         :ok <- validate_description_quality(normalized_data),
         :ok <- validate_dates(normalized_data) do
      # Calculate quality score
      quality_score = calculate_quality_score(normalized_data)
      
      {:ok, Map.put(normalized_data, :quality_score, quality_score)}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp validate_required_fields(data) do
    required = [:title, :company_name, :description]
    
    missing = Enum.filter(required, fn field ->
      is_nil(Map.get(data, field)) or Map.get(data, field) == ""
    end)
    
    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_required_fields, missing}}
    end
  end
  
  defp validate_company_name(data) do
    name = data.company_name
    
    cond do
      String.length(name) < 2 -> {:error, :company_name_too_short}
      name =~ ~r/[0-9]{5,}/ -> {:error, :company_name_looks_invalid}
      true -> :ok
    end
  end
  
  defp validate_description_quality(data) do
    desc = data.description
    word_count = desc |> String.split() |> length()
    
    cond do
      word_count < 20 -> {:error, :description_too_short}
      word_count > 5000 -> {:error, :description_suspiciously_long}
      true -> :ok
    end
  end
  
  defp calculate_quality_score(data) do
    score = 0
    
    # Required fields present = 40 points
    score = score + 40
    
    # Has salary = 15 points
    score = if data.salary_min, do: score + 15, else: score
    
    # Has closing date = 10 points
    score = if data.closing_date, do: score + 10, else: score
    
    # Description length
    word_count = data.description |> String.split() |> length()
    score = if word_count > 100, do: score + 15, else: score + 5
    
    # Has requirements = 10 points
    score = if data.requirements, do: score + 10, else: score
    
    # Has job type = 10 points
    score = if data.job_type, do: score + 10, else: score
    
    min(score, 100)
  end
end
```

**Key Points:**
- Validates data structure
- Calculates quality score
- No database access
- Returns validated data or errors

---

### 4. Ingestion (Side Effects / Storage)

```elixir
# lib/hirehound/jobs/ingestion.ex
defmodule Hirehound.Jobs.Ingestion do
  @moduledoc """
  Handles saving validated job data to the database.
  
  This is the ONLY module that performs database writes for jobs.
  All storage logic is centralized here.
  """
  
  alias Hirehound.{Repo, Jobs, Companies}
  alias Jobs.JobPosting
  
  def save(validated_data) do
    Repo.transaction(fn ->
      # 1. Find or create company
      {:ok, company} = find_or_create_company(validated_data)
      
      # 2. Build job posting changeset
      attrs = Map.put(validated_data, :company_id, company.id)
      changeset = JobPosting.changeset(%JobPosting{}, attrs)
      
      # 3. Insert job posting
      case Repo.insert(changeset) do
        {:ok, job_posting} ->
          # 4. Update company stats
          update_company_stats(company)
          
          job_posting
          
        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end
  
  def save_batch(validated_data_list) do
    # Efficient batch insertion
    Enum.map(validated_data_list, &save/1)
  end
  
  defp find_or_create_company(job_data) do
    # Try to find existing company by normalized name
    normalized_name = job_data.company_name
    
    case Repo.get_by(Companies.Company, name: normalized_name) do
      nil ->
        # Create new company
        %Companies.Company{}
        |> Companies.Company.changeset(%{
          name: normalized_name,
          slug: Slug.slugify(normalized_name),
          raw_data: %{
            source_name: job_data.source_name,
            original_name: job_data.company_name_raw
          }
        })
        |> Repo.insert()
        
      company ->
        {:ok, company}
    end
  end
  
  defp update_company_stats(company) do
    # Update denormalized stats
    Companies.Stats.increment_job_count(company.id)
  end
end
```

**Key Points:**
- **Single point of control** for storage
- Handles company matching/creation
- Transaction-safe
- Easy to modify without touching scrapers

---

### 5. Workers Orchestrate the Pipeline

```elixir
# lib/hirehound/workers/listing_crawler.ex
defmodule Hirehound.Workers.ListingCrawler do
  use Oban.Worker, 
    queue: :scraping,
    unique: [period: 60, fields: [:args]]
  
  alias Hirehound.Scrapers
  
  @impl Oban.Worker
  def perform(%Job{args: %{"url" => url, "board" => board}}) do
    scraper = Scrapers.get_scraper(board)
    
    # 1. Scrape (pure - returns data)
    {:ok, job_summaries} = scraper.scrape_listing_page(url)
    
    # 2. Enqueue detail page scrapers for each job
    Enum.each(job_summaries, fn summary ->
      if summary.detail_url do
        %{url: summary.detail_url, board: board}
        |> Workers.DetailScraper.new(unique: [period: 3600])
        |> Oban.insert()
      end
    end)
    
    # 3. Continue pagination
    if scraper.has_next_page?(html) do
      next_url = scraper.next_page_url(html)
      
      %{url: next_url, board: board}
      |> Workers.ListingCrawler.new(unique: [period: 60])
      |> Oban.insert()
    end
    
    :ok
  end
end
```

```elixir
# lib/hirehound/workers/detail_scraper.ex
defmodule Hirehound.Workers.DetailScraper do
  use Oban.Worker, 
    queue: :processing,
    unique: [period: 3600, fields: [:args]]
  
  alias Hirehound.{Scrapers, Jobs}
  
  @impl Oban.Worker
  def perform(%Job{args: %{"url" => url, "board" => board}}) do
    scraper = Scrapers.get_scraper(board)
    
    # Pipeline: scrape → normalize → validate → save
    with {:ok, raw_data} <- scraper.scrape_detail_page(url),
         {:ok, normalized} <- Jobs.Normalization.normalize(raw_data),
         {:ok, validated} <- Jobs.Validation.validate(normalized),
         {:ok, job_posting} <- Jobs.Ingestion.save(validated) do
      
      # Enqueue deduplication
      %{job_posting_id: job_posting.id}
      |> Workers.DeduplicationWorker.new()
      |> Oban.insert()
      
      {:ok, job_posting}
    else
      {:error, reason} ->
        # Log validation/scraping failure, don't crash
        Logger.warning("Failed to process job: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
```

**Key Points:**
- Workers orchestrate the pipeline
- Each step is separate (scrape, normalize, validate, save)
- Easy to add preview/dry-run mode
- Clear error boundaries

---

## Testing Strategy

### Test Scrapers (Pure Functions)

```elixir
# test/hirehound/scrapers/pnet_scraper_test.exs
defmodule Hirehound.Scrapers.PNetScraperTest do
  use ExUnit.Case
  use ExVCR.Mock, adapter: ExVCR.Adapter.Finch
  
  alias Hirehound.Scrapers.PNetScraper
  
  describe "scrape_detail_page/1" do
    test "extracts all job fields correctly" do
      use_cassette "pnet_detail_page" do
        url = "https://www.pnet.co.za/jobs/12345"
        
        # NO DATABASE SETUP NEEDED!
        assert {:ok, job_data} = PNetScraper.scrape_detail_page(url)
        
        # Test extracted data structure
        assert job_data.title == "Senior Developer"
        assert job_data.company_name == "Google (Pty) Ltd"
        assert job_data.location == "Cape Town, Western Cape"
        assert job_data.source_name == "pnet"
        assert job_data.source_url == url
        assert is_binary(job_data.description)
        assert String.length(job_data.description) > 100
      end
    end
    
    test "handles missing salary gracefully" do
      use_cassette "pnet_no_salary" do
        {:ok, job_data} = PNetScraper.scrape_detail_page("...")
        
        assert is_nil(job_data.salary)
      end
    end
  end
end
```

### Test Normalization (Pure Functions)

```elixir
# test/hirehound/jobs/normalization_test.exs
defmodule Hirehound.Jobs.NormalizationTest do
  use ExUnit.Case
  
  alias Hirehound.Jobs.Normalization
  
  test "normalizes company names" do
    raw_data = %{
      title: "Developer",
      company_name: "Google (Pty) Ltd",
      description: "...",
      location: "Cape Town",
      source_name: "pnet",
      scraped_at: DateTime.utc_now()
    }
    
    {:ok, normalized} = Normalization.normalize(raw_data)
    
    assert normalized.company_name == "google"
    assert normalized.company_name_raw == "Google (Pty) Ltd"
  end
  
  test "parses provinces correctly" do
    raw_data = %{
      title: "Dev",
      company_name: "Test Co",
      description: "...",
      location: "Cape Town, Western Cape",
      source_name: "pnet",
      scraped_at: DateTime.utc_now()
    }
    
    {:ok, normalized} = Normalization.normalize(raw_data)
    
    assert normalized.province == "Western Cape"
    assert normalized.city == "Cape Town"
  end
end
```

### Test Ingestion (Database)

```elixir
# test/hirehound/jobs/ingestion_test.exs
defmodule Hirehound.Jobs.IngestionTest do
  use Hirehound.DataCase  # Sets up DB
  
  alias Hirehound.Jobs.Ingestion
  
  test "saves job and creates company if needed" do
    validated_data = %{
      title: "Senior Developer",
      company_name: "google",
      company_name_raw: "Google (Pty) Ltd",
      description: "Test description",
      province: "Gauteng",
      quality_score: 85,
      source_name: "pnet",
      source_url: "https://...",
      scraped_at: DateTime.utc_now()
    }
    
    assert {:ok, job_posting} = Ingestion.save(validated_data)
    
    assert job_posting.title == "Senior Developer"
    assert job_posting.company_id
    
    # Company was created
    company = Repo.get(Company, job_posting.company_id)
    assert company.name == "google"
  end
end
```

---

## IEx Workflow (No Database Required!)

```elixir
$ iex -S mix

# Scrape without saving
iex> alias Hirehound.Scrapers.PNetScraper
iex> {:ok, job_data} = PNetScraper.scrape_detail_page("https://pnet.co.za/jobs/12345")
{:ok, %{title: "Senior Developer", company_name: "Google", ...}}

# Inspect data
iex> job_data.description |> String.slice(0, 200)

# Normalize (still no DB!)
iex> alias Hirehound.Jobs.Normalization
iex> {:ok, normalized} = Normalization.normalize(job_data)
{:ok, %{company_name: "google", province: "Gauteng", ...}}

# Validate
iex> alias Hirehound.Jobs.Validation
iex> {:ok, validated} = Validation.validate(normalized)
{:ok, %{quality_score: 85, ...}}

# Only NOW save to DB (if you want)
iex> alias Hirehound.Jobs.Ingestion
iex> {:ok, job_posting} = Ingestion.save(validated)
{:ok, %JobPosting{id: "...", title: "Senior Developer"}}
```

---

## Adding Dry-Run / Preview Mode

```elixir
# lib/hirehound/workers/detail_scraper.ex
defmodule Hirehound.Workers.DetailScraper do
  use Oban.Worker, queue: :processing
  
  @impl Oban.Worker
  def perform(%Job{args: args}) do
    dry_run = Map.get(args, "dry_run", false)
    
    with {:ok, raw_data} <- scrape(args),
         {:ok, normalized} <- Jobs.Normalization.normalize(raw_data),
         {:ok, validated} <- Jobs.Validation.validate(normalized) do
      
      if dry_run do
        # Just log, don't save
        Logger.info("DRY RUN: Would save job: #{validated.title}")
        {:ok, validated}
      else
        # Normal save
        Jobs.Ingestion.save(validated)
      end
    end
  end
end

# Usage in IEx
iex> %{url: "...", board: "pnet", dry_run: true}
     |> Workers.DetailScraper.new()
     |> Oban.insert()
# Scrapes and validates, but doesn't save!
```

---

## Migration Path

### Phase 1: Current State (Start Here)

Keep scrapers pure from day 1:
- ✅ Scrapers return data
- ✅ Normalization is pure
- ✅ Storage in `Ingestion.save/1`
- ⚠️ No validation yet (validate in Ingestion for now)

### Phase 2: Add Validation (Week 2-3)

Once schema stabilizes:
- ✅ Add `Validation` module
- ✅ Calculate quality scores
- ✅ Reject low-quality jobs

### Phase 3: Preview/Approval (Month 2)

When ready for admin UI:
- ✅ Add `dry_run` mode
- ✅ Preview scraped jobs before saving
- ✅ Admin approval workflow

---

## Summary

**The Golden Rule:** Scrapers extract data, Workers orchestrate storage.

**What's Pure:**
- ✅ Scrapers: `scrape_*` → returns data
- ✅ Normalization: transforms data
- ✅ Validation: checks quality

**What Has Side Effects:**
- ❌ Ingestion: saves to DB
- ❌ Workers: orchestrate pipeline

**Result:** Testable, flexible, debuggable scraping system with clean separation of concerns.
