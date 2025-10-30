# PNet Scraper - IEx Exploration Notes

**Date:** October 29, 2025  
**URL Explored:** `https://www.pnet.co.za/jobs`  
**Page Type:** Listing page (shows 25 jobs per page)

## Working Selectors

| Data Field | Selector | Notes |
|------------|----------|-------|
| **Job Cards** | `article[data-at='job-item']` | Returns 25 jobs per page |
| **Job Title** | `[data-at='job-item-title'] .res-ewgtgq` | Clean text in nested div |
| **Company Name** | `[data-at='job-item-company-name'] .res-ewgtgq` | Clean text in nested div |
| **Location** | `[data-at='job-item-location']` | No CSS noise |
| **Salary** | `[data-at='job-item-salary-info']` | Often empty string |
| **Posted Date** | `[data-at='job-item-timeago']` | Relative ("1 hour ago") |
| **Detail URL** | `[data-at='job-item-title']` href attribute | Relative path |

## Working IEx Code

```elixir
# 1. Fetch the listing page
url = "https://www.pnet.co.za/jobs"
{:ok, response} = Req.get(url)

# 2. Parse HTML
html = response.body
doc = Floki.parse_document!(html)

# 3. Find all job cards
cards = Floki.find(doc, "article[data-at='job-item']")
length(cards)  # => 25

# 4. Extract data from first job
first = List.first(cards)
title = Floki.find(first, "[data-at='job-item-title'] .res-ewgtgq") |> Floki.text()
company = Floki.find(first, "[data-at='job-item-company-name'] .res-ewgtgq") |> Floki.text()
location = Floki.find(first, "[data-at='job-item-location']") |> Floki.text()
salary = Floki.find(first, "[data-at='job-item-salary-info']") |> Floki.text()
detail_url = Floki.find(first, "[data-at='job-item-title']") |> Floki.attribute("href") |> List.first()
posted = Floki.find(first, "[data-at='job-item-timeago']") |> Floki.text()

# 5. Extract all 25 jobs
jobs = Enum.map(cards, fn card ->
  %{
    title: Floki.find(card, "[data-at='job-item-title'] .res-ewgtgq") |> Floki.text(),
    company: Floki.find(card, "[data-at='job-item-company-name'] .res-ewgtgq") |> Floki.text(),
    location: Floki.find(card, "[data-at='job-item-location']") |> Floki.text(),
    salary: Floki.find(card, "[data-at='job-item-salary-info']") |> Floki.text(),
    detail_url: Floki.find(card, "[data-at='job-item-title']") |> Floki.attribute("href") |> List.first(),
    posted: Floki.find(card, "[data-at='job-item-timeago']") |> Floki.text()
  }
end)

# 6. Inspect results
length(jobs)  # => 25
List.first(jobs) |> IO.inspect()
```

## Sample Output

```elixir
%{
  title: "Clinical Facilitator (Registered Nurse)",
  company: "Fides Recruitment",
  location: "Hermanus",
  salary: "R30 000 to R40 000",
  detail_url: "/jobs--Clinical-Facilitator-Registered-Nurse-Hermanus-Fides-Recruitment--4083030-inline.html",
  posted: "1 hour ago"
}
```

## Observations

✅ **Page Type:** Listing page - shows multiple jobs  
✅ **Pagination:** Has "Next" link at bottom (page 1 of 639)  
✅ **Detail Pages:** Need to visit detail URL for full job description  
✅ **Data Quality:** Salary often missing, location is clean, company names look good  
✅ **Rate Limiting:** Need to add delays (PNet metadata says 100 req/min limit)  

## Next Steps

1. **Explore a detail page** - Fetch one detail_url to see full job data
2. **Create scraper module** - Codify this into `lib/hirehound/scrapers/pnet_scraper.ex`
3. **Handle pagination** - Extract next page URL
4. **Add to schema** - Create database tables for jobs and companies

## URL Patterns for Auto-Routing

```elixir
# For Scrapers.Behaviour url_patterns/0 callback
%{
  domains: ["pnet.co.za"],
  listing_path_pattern: ~r{^/jobs/?(\?.*)?$},      # /jobs or /jobs?page=2
  detail_path_pattern: ~r{^/jobs--.*\.html$}       # /jobs--{title}--{id}-inline.html
}
```

## Metadata

```elixir
# For Scrapers.Behaviour metadata/0 callback
%{
  name: "PNet",
  base_url: "https://www.pnet.co.za",
  rate_limit: 100,  # requests per minute (from docs)
  scraping_frequency: :hourly,
  requires_detail_page: true  # Listing doesn't have full description
}
```
