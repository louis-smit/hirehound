# Deduplication Strategy

## Overview

Duplicate detection is the most critical challenge for Hirehound. We need sophisticated deduplication for **two entity types**:

### 1. Job Posting Deduplication
The same job posting often appears on multiple job boards with variations in:
- Formatting and markup
- Completeness (some fields missing on some sources)
- Posting dates (may differ by days)
- Job IDs (each source has its own)

### 2. Organization Deduplication
The same company appears with different names/spellings across sources:
- "ABC Company (Pty) Ltd" vs "ABC Company" vs "ABC Co."
- Subsidiaries and parent companies
- Franchise locations
- Historical name changes
- Acquisitions and mergers

**Both require sophisticated, multi-stage deduplication pipelines** orchestrated through background job workflows (see [Workflow Orchestration](./05-workflow-orchestration.md)).

## Types of Duplicates

### 1. Exact Duplicates
**Definition:** Byte-for-byte identical or near-identical content

**Detection Method:**
- Hash the normalized title + company + location
- Store in `combined_hash` field
- Index for fast lookup

**Example:**
```sql
-- Exact duplicate detection
SELECT * FROM job_postings 
WHERE combined_hash = md5(normalize(title || company_name || location))
```

### 2. Near Duplicates
**Definition:** Same job with minor textual variations

**Detection Method:**
- MinHash/LSH (Locality-Sensitive Hashing) on description
- Jaccard similarity on tokenized text
- Threshold: 85%+ similarity = likely duplicate

**Implementation:**
```elixir
# Pseudo-code
def find_near_duplicates(job_posting) do
  fingerprint = MinHash.generate(job_posting.description)
  
  JobPosting
  |> where([j], fragment("minhash_similarity(?, ?) > 0.85", j.description_fingerprint, ^fingerprint))
  |> where([j], j.company_id == ^job_posting.company_id)
end
```

### 3. Fuzzy Duplicates
**Definition:** Same job with significant rewording or different sources

**Detection Method:**
- Multi-stage matching pipeline
- Combine multiple signals with weighted scoring

**Signals:**
1. **Title Similarity** (30% weight)
   - Levenshtein distance
   - Token overlap
   - Semantic similarity (embeddings)

2. **Company Match** (25% weight)
   - Exact name match
   - Known aliases
   - Normalized comparison

3. **Location Match** (15% weight)
   - Same city/province
   - Geographic proximity

4. **Description Similarity** (20% weight)
   - TF-IDF cosine similarity
   - Key phrase extraction
   - Semantic embeddings

5. **Temporal Proximity** (10% weight)
   - Posted within 7 days of each other
   - Salary ranges overlap
   - Job type matches

**Scoring:**
```
total_score = (title_sim * 0.30) +
              (company_match * 0.25) +
              (location_match * 0.15) +
              (description_sim * 0.20) +
              (temporal_match * 0.10)

if total_score > 0.75:
  LIKELY_DUPLICATE
elif total_score > 0.60:
  POSSIBLE_DUPLICATE (requires review)
else:
  UNIQUE
```

## Deduplication Architecture

### Multi-Stage Pipeline

```
New Job Posting
    ↓
[Stage 1: Exact Hash Lookup]
    ↓ (if no exact match)
[Stage 2: Near Duplicate Detection]
    ↓ (if no near match)
[Stage 3: Fuzzy Matching]
    ↓
[Cluster Assignment]
    ↓
Database Storage
```

### Database Schema for Duplicates

```sql
-- Main job postings table
CREATE TABLE job_postings (
  id UUID PRIMARY KEY,
  duplicate_cluster_id UUID,
  is_canonical BOOLEAN DEFAULT false,
  -- ... other fields
);

-- Duplicate clusters (groups of related job postings)
CREATE TABLE duplicate_clusters (
  id UUID PRIMARY KEY,
  canonical_job_id UUID REFERENCES job_postings(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  member_count INTEGER DEFAULT 1,
  confidence_score DECIMAL(3,2) -- 0.00 to 1.00
);

-- Individual duplicate relationships
CREATE TABLE duplicate_relationships (
  id UUID PRIMARY KEY,
  job_id_1 UUID REFERENCES job_postings(id),
  job_id_2 UUID REFERENCES job_postings(id),
  similarity_score DECIMAL(3,2),
  match_type VARCHAR(20), -- 'exact', 'near', 'fuzzy'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT unique_pair UNIQUE(job_id_1, job_id_2)
);

-- Indexes for performance
CREATE INDEX idx_cluster_id ON job_postings(duplicate_cluster_id);
CREATE INDEX idx_combined_hash ON job_postings(combined_hash);
CREATE INDEX idx_title_fingerprint ON job_postings USING gin(title_fingerprint);
```

### Clustering Algorithm

**Goal:** Group all duplicate job postings into clusters

**Approach:** Connected Components with Confidence Thresholding

```elixir
defmodule Hirehound.Deduplication.Clustering do
  @moduledoc """
  Groups job postings into duplicate clusters using graph-based approach.
  """
  
  def cluster_duplicates(threshold \\ 0.75) do
    # 1. Build graph of all duplicate relationships above threshold
    edges = DuplicateRelationship
    |> where([r], r.similarity_score >= ^threshold)
    |> Repo.all()
    
    # 2. Find connected components (each component = one cluster)
    clusters = Graph.connected_components(edges)
    
    # 3. For each cluster, select canonical posting
    Enum.each(clusters, fn cluster ->
      canonical = select_canonical(cluster)
      update_cluster(cluster, canonical)
    end)
  end
  
  defp select_canonical(job_postings) do
    # Canonical selection criteria (in order of priority):
    # 1. Highest quality score (most complete data)
    # 2. From most authoritative source (company site > LinkedIn > PNet > others)
    # 3. Most recent posting
    # 4. Longest description
    
    job_postings
    |> Enum.sort_by(&canonical_score/1, :desc)
    |> List.first()
  end
  
  defp canonical_score(job) do
    quality_score = job.quality_score * 100
    source_score = source_authority_score(job.source_name)
    recency_score = recency_score(job.posted_date)
    
    quality_score + source_score + recency_score
  end
end
```

## Handling Edge Cases

### Case 1: Job Reposted After Expiry
**Scenario:** Same company reposts same job after closing

**Solution:**
- Check if posting is >30 days after previous
- Create new cluster or mark as "reposting"
- Maintain relationship but don't merge

### Case 2: Multiple Positions for Same Role
**Scenario:** Company hiring 5 software engineers, posts separately

**Solution:**
- Look for "X positions available" in description
- Check for "Ref: XXX-1", "Ref: XXX-2" patterns
- Don't cluster if position IDs differ

### Case 3: Similar Roles, Different Teams
**Scenario:** Large company hiring same role in different departments

**Solution:**
- Extract department/team from description
- Use stricter matching when company is large (>1000 employees)
- Require location match for large companies

### Case 4: Franchises/Branches
**Scenario:** Same franchise role posted in multiple locations

**Solution:**
- Detect franchise patterns in company name
- Allow clustering only within same geographic area
- Use location as strong signal

## Performance Optimization

### 1. Candidate Generation
Don't compare every job to every other job (O(n²) is too slow)

**Strategy: Blocking**
Only compare jobs that share certain characteristics:
- Same company (primary block)
- Same job category
- Same province
- Posted within 30 days

```sql
-- Example: Find candidates for comparison
WITH target AS (
  SELECT * FROM job_postings WHERE id = ?
)
SELECT j.*
FROM job_postings j
WHERE j.company_id = target.company_id
  AND j.province = target.province
  AND j.posted_date BETWEEN target.posted_date - INTERVAL '30 days' 
                        AND target.posted_date + INTERVAL '30 days'
  AND j.id != target.id;
```

### 2. Incremental Processing
- Only check new jobs against recent jobs
- Reprocess old jobs periodically (monthly)
- Use job queue for asynchronous processing

### 3. Caching
- Cache company normalization lookups
- Cache skill extraction for descriptions
- Cache embedding vectors

### 4. Indexing
```sql
-- Full-text search index
CREATE INDEX idx_description_fts ON job_postings USING gin(search_vector);

-- Similarity search indexes
CREATE INDEX idx_company_id ON job_postings(company_id);
CREATE INDEX idx_posted_date ON job_postings(posted_date);
CREATE INDEX idx_province ON job_postings(province);

-- Composite index for blocking
CREATE INDEX idx_blocking ON job_postings(company_id, province, posted_date);
```

## Machine Learning Enhancement (Future)

### Supervised Learning Approach

1. **Training Data:**
   - Manually label 5,000+ job pairs as duplicate/not duplicate
   - Include borderline cases
   - Balance positive and negative examples

2. **Features:**
   - All similarity scores from fuzzy matching
   - Statistical features (word count ratio, char count ratio)
   - Metadata features (source, posting time delta)
   - Derived features (title length difference, description overlap)

3. **Model:**
   - Gradient Boosting (XGBoost/LightGBM)
   - Neural network with embedding layer
   - Output: Probability of duplicate (0.0 to 1.0)

4. **Deployment:**
   - Train in Python
   - Export to ONNX
   - Load in Elixir using Nx/Axon
   - Use for real-time scoring

## Monitoring & Metrics

### Quality Metrics

```elixir
# Track deduplication accuracy
defmodule Hirehound.Metrics.Deduplication do
  def calculate_metrics do
    %{
      # Cluster purity: % of clusters with all members truly duplicates
      cluster_purity: calculate_cluster_purity(),
      
      # Precision: % of identified duplicates that are actually duplicates
      precision: true_positives / (true_positives + false_positives),
      
      # Recall: % of actual duplicates that we identified
      recall: true_positives / (true_positives + false_negatives),
      
      # Cluster distribution
      cluster_sizes: cluster_size_histogram(),
      
      # Processing time
      avg_dedup_time_ms: average_deduplication_time()
    }
  end
end
```

### Alerting Thresholds

- Alert if precision drops below 90%
- Alert if avg cluster size > 10 (may indicate over-clustering)
- Alert if >20% of new jobs form singletons (may indicate under-clustering)
- Alert if dedup processing time > 5 seconds per job

## UI Considerations

### User-Facing Deduplication

**Option 1: Show only canonical**
- Display single "best" version
- Link to "View X other sources" modal

**Option 2: Merge view**
- Combine data from all sources
- Show "Posted on: PNet, LinkedIn, CareerJunction"
- Use most complete data fields

**Option 3: Comparison view**
- Side-by-side comparison
- Highlight differences
- Let users choose preferred version

### Admin Interface

- Manual merge/unmerge tools
- Duplicate review queue for borderline cases
- Analytics dashboard for duplicate patterns
- Company alias management

---

# Organization Deduplication

Organization deduplication is equally critical and uses similar techniques but with organization-specific signals.

## Organization Deduplication Pipeline

### Stage 1: Exact Name Matching
```elixir
defmodule Hirehound.Deduplication.OrgExactMatcher do
  def find_exact_matches(org) do
    normalized_name = normalize_org_name(org.name)
    hash = :crypto.hash(:md5, normalized_name) |> Base.encode16()
    
    Organization
    |> where([o], o.name_hash == ^hash)
    |> where([o], o.id != ^org.id)
    |> Repo.all()
  end
  
  defp normalize_org_name(name) do
    name
    |> String.downcase()
    |> remove_legal_entities()  # Remove "Pty Ltd", "Inc", etc.
    |> String.replace(~r/[^\w\s]/, "")  # Remove punctuation
    |> String.trim()
  end
  
  defp remove_legal_entities(name) do
    legal_suffixes = [
      "pty ltd", "(pty) ltd", "pty", "ltd", "limited",
      "inc", "incorporated", "corp", "corporation",
      "llc", "plc", "gmbh", "sa", "npc"
    ]
    
    Enum.reduce(legal_suffixes, name, fn suffix, acc ->
      String.replace(acc, ~r/\s+#{suffix}$/i, "")
    end)
  end
end
```

### Stage 2: Website/Domain Matching
**Signal:** Organizations with the same website are almost certainly the same entity

```sql
-- Find organizations with matching domains
SELECT o1.id, o2.id, o1.canonical_name, o2.canonical_name
FROM organizations o1
JOIN organizations o2 ON extract_domain(o1.website_url) = extract_domain(o2.website_url)
WHERE o1.id < o2.id
  AND o1.website_url IS NOT NULL
  AND o2.website_url IS NOT NULL;
```

### Stage 3: Registration Number Matching
**Signal:** South African company registration numbers are unique

```elixir
defmodule Hirehound.Deduplication.OrgRegistrationMatcher do
  def find_by_registration(org) do
    if org.registration_number do
      Organization
      |> where([o], o.registration_number == ^org.registration_number)
      |> where([o], o.id != ^org.id)
      |> Repo.all()
    else
      []
    end
  end
end
```

### Stage 4: Fuzzy Matching with Multiple Signals

**Signals & Weights:**
1. **Name Similarity** (40%) - Levenshtein, Jaro-Winkler
2. **Location Match** (20%) - Same city/province
3. **Industry Match** (15%) - Same industry
4. **Website Similarity** (15%) - Similar domains
5. **Contact Info** (10%) - Email/phone overlap

```elixir
defmodule Hirehound.Deduplication.OrgFuzzyMatcher do
  def calculate_similarity(org1, org2) do
    %{
      name_score: name_similarity(org1, org2) * 0.40,
      location_score: location_match(org1, org2) * 0.20,
      industry_score: industry_match(org1, org2) * 0.15,
      website_score: website_similarity(org1, org2) * 0.15,
      contact_score: contact_match(org1, org2) * 0.10
    }
    |> Map.values()
    |> Enum.sum()
  end
  
  defp name_similarity(org1, org2) do
    # Try multiple algorithms, take max
    levenshtein = String.jaro_distance(org1.canonical_name, org2.canonical_name)
    token_overlap = token_jaccard_similarity(org1.canonical_name, org2.canonical_name)
    
    max(levenshtein, token_overlap)
  end
  
  defp token_jaccard_similarity(name1, name2) do
    tokens1 = name1 |> String.downcase() |> String.split() |> MapSet.new()
    tokens2 = name2 |> String.downcase() |> String.split() |> MapSet.new()
    
    intersection = MapSet.intersection(tokens1, tokens2) |> MapSet.size()
    union = MapSet.union(tokens1, tokens2) |> MapSet.size()
    
    if union > 0, do: intersection / union, else: 0.0
  end
end
```

## Organization Alias Management

Track known aliases and variations in a dedicated table:

```sql
CREATE TABLE organization_aliases (
  id UUID PRIMARY KEY,
  organization_id UUID REFERENCES organizations(id),
  alias_name VARCHAR(255) NOT NULL,
  alias_type VARCHAR(50), -- 'legal', 'trading', 'acronym', 'former', 'common_misspelling'
  is_primary BOOLEAN DEFAULT false,
  source VARCHAR(100), -- where we learned this alias
  verified BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_org_alias_name ON organization_aliases(alias_name);
CREATE INDEX idx_org_alias_org_id ON organization_aliases(organization_id);
```

### Alias Discovery Workflow

```elixir
defmodule Hirehound.Workflows.OrgAliasDiscovery do
  use Oban.Pro.Workflow
  
  def discover_aliases(org_id) do
    org_id
    |> new_extract_from_jobs()      # Find variations in job postings
    |> new_linkedin_scrape()         # Get LinkedIn variations
    |> new_companies_house_lookup()  # Get official names from registry
    |> new_merge_aliases()           # Consolidate and deduplicate
  end
end
```

## Organization Clustering

Similar to job clustering, but with additional complexity for company hierarchies:

### Challenge: Parent/Subsidiary Relationships

```
Microsoft Corporation
  ├── Microsoft South Africa (Pty) Ltd  [subsidiary]
  ├── LinkedIn Corporation              [acquired company]
  └── GitHub, Inc.                      [acquired company]
```

**Strategy:**
- Don't merge parent/subsidiary into same organization
- Track relationships in separate `organization_relationships` table
- Use relationship type: parent, subsidiary, acquired, merged_into, formerly_known_as

```sql
CREATE TABLE organization_relationships (
  id UUID PRIMARY KEY,
  organization_id UUID REFERENCES organizations(id),
  related_organization_id UUID REFERENCES organizations(id),
  relationship_type VARCHAR(50),
  confidence_score DECIMAL(3,2),
  effective_date DATE,
  source VARCHAR(100),
  verified BOOLEAN DEFAULT false
);
```

## Deduplication Workflow Orchestration

All deduplication processes are orchestrated through sophisticated background job workflows (see [Workflow Orchestration](./05-workflow-orchestration.md)).

### Organization Deduplication Workflow

```elixir
defmodule Hirehound.Workflows.OrganizationDeduplication do
  use Oban.Pro.Workflow
  
  def deduplicate_organization(org_id) do
    Workflow.new()
    # Stage 1: Quick exact checks
    |> Workflow.add(
        :exact_match,
        Workers.OrgExactMatcher.new(%{org_id: org_id}),
        queue: :deduplication
      )
    
    # Stage 2: Registration/domain checks (in parallel)
    |> Workflow.add(
        :registration_check,
        Workers.OrgRegistrationMatcher.new(%{org_id: org_id}),
        queue: :deduplication
      )
    |> Workflow.add(
        :domain_check,
        Workers.OrgDomainMatcher.new(%{org_id: org_id}),
        queue: :deduplication
      )
    
    # Stage 3: Fuzzy matching (only if no exact match)
    |> Workflow.add(
        :fuzzy_match,
        Workers.OrgFuzzyMatcher.new(%{org_id: org_id}),
        deps: [:exact_match, :registration_check, :domain_check],
        queue: :deduplication,
        condition: fn results ->
          # Only run fuzzy if no exact matches found
          Enum.all?(results, fn {_stage, matches} -> Enum.empty?(matches) end)
        end
      )
    
    # Stage 4: Clustering decision
    |> Workflow.add(
        :cluster,
        Workers.OrgClustering.new(%{org_id: org_id}),
        deps: [:exact_match, :registration_check, :domain_check, :fuzzy_match],
        queue: :deduplication
      )
    
    # Stage 5: Update related jobs
    |> Workflow.add(
        :update_jobs,
        Workers.PropagateOrgChanges.new(%{org_id: org_id}),
        deps: [:cluster],
        queue: :processing
      )
  end
end
```

### Job Deduplication Workflow

```elixir
defmodule Hirehound.Workflows.JobDeduplication do
  use Oban.Pro.Workflow
  
  def deduplicate_job(job_id) do
    Workflow.new()
    # Stage 1: Hash-based exact match
    |> Workflow.add(
        :exact_hash,
        Workers.JobExactMatcher.new(%{job_id: job_id}),
        queue: :deduplication,
        priority: 1
      )
    
    # Stage 2: Near duplicate (only if no exact match)
    |> Workflow.add(
        :near_duplicate,
        Workers.JobNearMatcher.new(%{job_id: job_id}),
        deps: [:exact_hash],
        queue: :deduplication,
        condition: &no_exact_match?/1
      )
    
    # Stage 3: Fuzzy matching (only if no near match)
    |> Workflow.add(
        :fuzzy_match,
        Workers.JobFuzzyMatcher.new(%{job_id: job_id}),
        deps: [:near_duplicate],
        queue: :deduplication,
        condition: &no_near_match?/1
      )
    
    # Stage 4: Clustering
    |> Workflow.add(
        :cluster,
        Workers.JobClustering.new(%{job_id: job_id}),
        deps: [:exact_hash, :near_duplicate, :fuzzy_match],
        queue: :deduplication
      )
    
    # Stage 5: Index update
    |> Workflow.add(
        :index,
        Workers.UpdateSearchIndex.new(%{job_id: job_id}),
        deps: [:cluster],
        queue: :indexing
      )
  end
  
  defp no_exact_match?(results) do
    case results[:exact_hash] do
      {:ok, []} -> true
      {:ok, nil} -> true
      _ -> false
    end
  end
end
```

## Monitoring Deduplication Quality

### Metrics Dashboard

```elixir
defmodule Hirehound.Metrics.Deduplication do
  def org_metrics do
    %{
      # How many organizations in database
      total_orgs: count_organizations(),
      
      # How many are in clusters
      clustered_orgs: count_clustered_organizations(),
      
      # Average cluster size
      avg_cluster_size: average_cluster_size(:organization),
      
      # Largest cluster (may indicate over-clustering)
      max_cluster_size: max_cluster_size(:organization),
      
      # Organizations pending deduplication
      pending_dedup: count_pending_dedup(:organization),
      
      # Precision/recall (requires labeled test set)
      precision: calculate_precision(:organization),
      recall: calculate_recall(:organization)
    }
  end
  
  def job_metrics do
    %{
      total_jobs: count_jobs(),
      clustered_jobs: count_clustered_jobs(),
      avg_cluster_size: average_cluster_size(:job),
      max_cluster_size: max_cluster_size(:job),
      pending_dedup: count_pending_dedup(:job),
      dedup_throughput_per_hour: jobs_deduped_last_hour(),
      avg_dedup_time_ms: average_dedup_time(:job)
    }
  end
end
```

### Alert Thresholds

- ⚠️ Organization cluster size > 5 (may be over-clustering)
- ⚠️ Job cluster size > 10 (may be over-clustering)
- ⚠️ Dedup queue depth > 1000 (falling behind)
- ⚠️ Dedup precision < 90% (too many false positives)
- 🚨 Dedup queue depth > 10000 (critical backlog)

## Summary

Our comprehensive deduplication strategy:

✅ **Dual entity deduplication** - Both jobs AND organizations
✅ **Multi-stage pipeline** - Exact → Near → Fuzzy for accuracy
✅ **Workflow orchestration** - Oban Pro manages complex pipelines (see [Workflow Orchestration](./05-workflow-orchestration.md))
✅ **Smart candidate generation** - Blocking prevents O(n²) comparisons
✅ **Organization alias tracking** - Handle name variations
✅ **Relationship modeling** - Track parent/subsidiary connections
✅ **Comprehensive monitoring** - Quality metrics and alerting
✅ **Background processing** - Asynchronous, scalable architecture

This architecture ensures high-quality deduplication across both entities while maintaining performance at scale.

## References

- [Entity Resolution Techniques](https://medium.com/data-science/entity-resolution-identifying-real-world-entities-in-noisy-data-3e8c59f4f41c)
- [MinHash for Duplicate Detection](https://en.wikipedia.org/wiki/MinHash)
- [Locality-Sensitive Hashing](https://en.wikipedia.org/wiki/Locality-sensitive_hashing)
- [Record Linkage Best Practices](https://recordlinkage.readthedocs.io/)
- [Organization Entity Resolution](https://dl.acm.org/doi/10.1145/3318464.3389708)
