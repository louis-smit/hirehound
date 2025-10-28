# Workflow Orchestration & Background Processing

## Overview

Hirehound relies heavily on asynchronous, sophisticated background processing for core operations. Rather than simple job queues, we need **workflow orchestration** to handle complex, multi-step processes with dependencies, retries, and conditional logic.

## Core Workflows

### 1. Job Ingestion Pipeline
```
New Job Scraped
    ↓
[Extract & Parse] → Store raw data
    ↓
[Content Cleaning] → HTML sanitization, text extraction
    ↓
[Normalization] → Standardize fields
    ↓
[Organization Matching] → Find or create organization
    ↓
[Skill Extraction] → NLP/keyword extraction
    ↓
[Vectorization] → Generate embeddings for semantic search
    ↓
[Deduplication Check] → Multi-stage duplicate detection
    ↓
[Clustering] → Assign to duplicate cluster
    ↓
[Indexing] → Update search indexes
    ↓
[Quality Scoring] → Calculate completeness score
    ↓
[Spam Detection] → ML-based spam filtering
    ↓
[Publication] → Mark as active/searchable
```

### 2. Organization Enrichment Pipeline
```
Organization Identified
    ↓
[Deduplication] → Match against existing orgs
    ↓
[Data Merging] → Consolidate from multiple sources
    ↓
[External Enrichment] → Fetch company data (LinkedIn, Clearbit)
    ↓
[Logo Scraping] → Extract company logo
    ↓
[Industry Classification] → Categorize industry
    ↓
[Size Estimation] → Infer company size
    ↓
[Location Geocoding] → Map headquarters location
    ↓
[Vectorization] → Generate org embeddings
    ↓
[Update Jobs] → Propagate changes to related jobs
```

### 3. Periodic Maintenance Workflows
```
Daily Cron
    ↓
[Job Expiry] → Mark old jobs as inactive
    ↓
[Re-scraping] → Check if active jobs still exist
    ↓
[Cluster Revalidation] → Verify duplicate clusters
    ↓
[Stats Calculation] → Update aggregate metrics
    ↓
[Index Optimization] → Rebuild search indexes
    ↓
[Cleanup] → Archive old data
```

## Orchestration Architecture

### Technology Stack

#### Primary: Oban Pro (Recommended)
**Why Oban Pro:**
- Native Elixir/PostgreSQL integration
- Built-in workflow engine (Oban.Pro.Workflow)
- Advanced features: batching, chunking, rate limiting
- Observability and metrics out of the box
- No external dependencies (Redis, etc.)

**Workflow Features:**
```elixir
defmodule Hirehound.Workflows.JobIngestion do
  use Oban.Pro.Workflow
  
  @impl Oban.Pro.Workflow
  def process(%Job{args: %{"job_posting_id" => id}}) do
    id
    |> new_parse_job()
    |> new_normalize_job()
    |> new_match_organization()
    |> new_extract_skills()
    |> new_vectorize()
    |> new_deduplicate()
    |> new_index()
    |> new_spam_check()
  end
  
  defp new_parse_job(id) do
    %{job_posting_id: id}
    |> Jobs.ParseWorker.new()
    |> Workflow.add(:parse)
  end
  
  defp new_normalize_job(workflow) do
    workflow
    |> Workflow.add(:normalize, Jobs.NormalizeWorker, 
        deps: [:parse],
        replace_args: &extract_job_id/1)
  end
  
  # ... chain continues with dependencies
end
```

#### Alternative: Temporal (If complexity grows)
**Why Temporal:**
- Industry-leading workflow orchestration
- Handles complex saga patterns
- Built-in versioning and migration
- Language-agnostic (can integrate non-Elixir services)
- Excellent observability

**When to use:**
- If we need to orchestrate across multiple services
- Complex compensation logic (saga patterns)
- Long-running workflows (days/weeks)
- Need for workflow versioning

#### Comparison Matrix

| Feature | Oban Pro | Temporal | Custom Queue |
|---------|----------|----------|--------------|
| Elixir Native | ✅ Yes | ❌ SDK | ✅ Yes |
| Workflow Engine | ✅ Built-in | ✅ Advanced | ❌ Manual |
| Dependencies | PostgreSQL only | Temporal server | Varies |
| Observability | ✅ Excellent | ✅ Best-in-class | ⚠️ Build yourself |
| Learning Curve | Low | Medium | Low |
| Cost | License fee | Self-host free | Free |
| Saga Patterns | ⚠️ Manual | ✅ Built-in | ❌ Manual |
| Scale | 10K+ jobs/sec | 100K+ jobs/sec | Depends |

**Decision:** Start with Oban Pro, evaluate Temporal if we need cross-service orchestration.

## Background Job Architecture

### Job Categories & Queues

```elixir
# config/config.exs
config :hirehound, Oban,
  repo: Hirehound.Repo,
  queues: [
    # High priority, low latency
    critical: [limit: 10, paused: false],
    
    # Scraping jobs (rate-limited)
    scraping: [limit: 5, rate_limit: [allowed: 100, period: 60]],
    
    # CPU-intensive processing
    processing: [limit: 20, paused: false],
    
    # Organization enrichment (external API calls)
    enrichment: [limit: 10, rate_limit: [allowed: 50, period: 60]],
    
    # ML/vectorization (GPU jobs if available)
    ml: [limit: 5, paused: false],
    
    # Search indexing
    indexing: [limit: 10, paused: false],
    
    # Deduplication (database-intensive)
    deduplication: [limit: 15, paused: false],
    
    # Low priority maintenance
    maintenance: [limit: 3, paused: false],
    
    # Scheduled periodic jobs
    cron: [limit: 5, paused: false]
  ],
  plugins: [
    # Cron scheduling
    {Oban.Plugins.Cron,
      crontab: [
        {"0 2 * * *", Hirehound.Workers.DailyMaintenance},
        {"*/15 * * * *", Hirehound.Workers.JobExpiryCheck},
        {"0 */6 * * *", Hirehound.Workers.ClusterRevalidation}
      ]},
    
    # Automatic pruning of completed jobs
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    
    # Track job metrics
    {Oban.Pro.Plugins.DynamicLifeline, rescue_after: :timer.minutes(30)},
    
    # Batch processing
    {Oban.Pro.Plugins.Batch, []}
  ]
```

### Worker Examples

#### 1. Job Processing Worker
```elixir
defmodule Hirehound.Workers.JobProcessor do
  use Oban.Worker,
    queue: :processing,
    max_attempts: 3,
    priority: 1
  
  @impl Oban.Worker
  def perform(%Job{args: %{"job_posting_id" => id, "step" => "normalize"}}) do
    job_posting = Jobs.get_posting!(id)
    
    with {:ok, normalized} <- Normalization.normalize_posting(job_posting),
         {:ok, _} <- Jobs.update_posting(job_posting, normalized) do
      
      # Trigger next step in workflow
      %{job_posting_id: id, step: "match_organization"}
      |> Hirehound.Workers.OrganizationMatcher.new()
      |> Oban.insert()
      
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
```

#### 2. Vectorization Worker
```elixir
defmodule Hirehound.Workers.VectorizationWorker do
  use Oban.Worker,
    queue: :ml,
    max_attempts: 2,
    priority: 2
  
  @impl Oban.Worker
  def perform(%Job{args: %{"job_posting_id" => id, "fields" => fields}}) do
    job_posting = Jobs.get_posting!(id)
    
    # Generate embeddings for semantic search
    embeddings = 
      fields
      |> Enum.map(fn field ->
        text = Map.get(job_posting, String.to_atom(field))
        {field, Hirehound.ML.Embeddings.generate(text)}
      end)
      |> Map.new()
    
    Jobs.update_embeddings(job_posting, embeddings)
  end
end
```

#### 3. Batch Deduplication Worker
```elixir
defmodule Hirehound.Workers.BatchDeduplication do
  use Oban.Pro.Workers.Batch,
    queue: :deduplication,
    max_batch_size: 100
  
  @impl true
  def process(%Job{args: %{"job_posting_ids" => ids}}) do
    # Process batch of jobs for deduplication
    Deduplication.process_batch(ids)
  end
  
  @impl true
  def handle_completed(jobs, batch) do
    # After all jobs in batch complete, run clustering
    %{batch_id: batch.id}
    |> Hirehound.Workers.ClusteringWorker.new()
    |> Oban.insert()
  end
end
```

#### 4. Organization Enrichment Worker
```elixir
defmodule Hirehound.Workers.OrganizationEnrichment do
  use Oban.Worker,
    queue: :enrichment,
    max_attempts: 5,
    priority: 3
  
  @impl Oban.Worker
  def perform(%Job{args: %{"organization_id" => id, "source" => source}}) do
    org = Organizations.get!(id)
    
    case source do
      "linkedin" -> 
        LinkedIn.API.fetch_company_data(org.linkedin_url)
        |> merge_into_organization(org)
        
      "clearbit" ->
        Clearbit.API.enrich_company(org.domain)
        |> merge_into_organization(org)
        
      "crunchbase" ->
        Crunchbase.API.fetch_company(org.name)
        |> merge_into_organization(org)
    end
  end
  
  defp merge_into_organization({:ok, data}, org) do
    Organizations.merge_external_data(org, data)
  end
end
```

## Specialized Processing Patterns

### 1. Spam Detection Pipeline
```elixir
defmodule Hirehound.Workflows.SpamDetection do
  use Oban.Pro.Workflow
  
  def detect_spam(job_posting_id) do
    job_posting_id
    |> new_rule_based_filter()      # Fast heuristics
    |> new_ml_classification()       # ML model
    |> new_similarity_check()        # Check against known spam
    |> new_update_spam_score()       # Update final score
  end
  
  defp new_rule_based_filter(id) do
    %{job_posting_id: id}
    |> Workers.RuleBasedSpamFilter.new(queue: :critical)
    |> Workflow.add(:rules)
  end
  
  defp new_ml_classification(workflow) do
    workflow
    |> Workflow.add(
        :ml_classify,
        Workers.MLSpamClassifier,
        deps: [:rules],
        queue: :ml
      )
  end
end
```

### 2. RAG (Retrieval-Augmented Generation) Indexing
```elixir
defmodule Hirehound.Workers.RAGIndexing do
  use Oban.Worker,
    queue: :ml,
    max_attempts: 2
  
  @impl Oban.Worker
  def perform(%Job{args: %{"type" => "job_posting", "id" => id}}) do
    job = Jobs.get_posting!(id)
    
    # Generate multiple embeddings for different aspects
    embeddings = %{
      title: embed_text(job.title),
      description: embed_text(job.description),
      requirements: embed_text(job.requirements),
      combined: embed_text("#{job.title} #{job.description}")
    }
    
    # Store in vector database (pgvector)
    VectorStore.upsert_job_embeddings(id, embeddings)
    
    # Update HNSW index for fast similarity search
    VectorStore.rebuild_index_if_needed()
  end
  
  @impl Oban.Worker
  def perform(%Job{args: %{"type" => "organization", "id" => id}}) do
    org = Organizations.get!(id)
    
    # Generate organization embedding
    embedding = embed_text("#{org.name} #{org.description} #{org.industry}")
    
    VectorStore.upsert_org_embedding(id, embedding)
  end
  
  defp embed_text(text) do
    # Use local model (BERT) or API (OpenAI)
    Hirehound.ML.Embeddings.generate(text)
  end
end
```

### 3. Incremental Indexing
```elixir
defmodule Hirehound.Workers.IncrementalIndexer do
  use Oban.Worker,
    queue: :indexing,
    max_attempts: 3
  
  @impl Oban.Worker
  def perform(%Job{args: %{"entity_type" => type, "entity_id" => id, "operation" => op}}) do
    case {type, op} do
      {"job_posting", "upsert"} ->
        job = Jobs.get_posting!(id)
        Search.Index.upsert_job(job)
        
      {"job_posting", "delete"} ->
        Search.Index.delete_job(id)
        
      {"organization", "upsert"} ->
        org = Organizations.get!(id)
        Search.Index.upsert_organization(org)
        
      {"organization", "delete"} ->
        Search.Index.delete_organization(id)
    end
  end
end
```

## Workflow Orchestration Patterns

### Pattern 1: Fan-Out / Fan-In
```elixir
# Process one job posting across multiple enrichment sources in parallel
defmodule Hirehound.Workflows.ParallelEnrichment do
  use Oban.Pro.Workflow
  
  def enrich_organization(org_id) do
    Workflow.new()
    |> Workflow.add(:linkedin, Workers.LinkedInEnrichment.new(%{org_id: org_id}))
    |> Workflow.add(:clearbit, Workers.ClearbitEnrichment.new(%{org_id: org_id}))
    |> Workflow.add(:crunchbase, Workers.CrunchbaseEnrichment.new(%{org_id: org_id}))
    |> Workflow.add(
        :merge,
        Workers.MergeEnrichmentData.new(%{org_id: org_id}),
        deps: [:linkedin, :clearbit, :crunchbase]
      )
  end
end
```

### Pattern 2: Conditional Branching
```elixir
defmodule Hirehound.Workflows.ConditionalProcessing do
  use Oban.Pro.Workflow
  
  def process_job(job_id) do
    Workflow.new()
    |> Workflow.add(:check_duplicate, Workers.QuickDuplicateCheck.new(%{job_id: job_id}))
    |> Workflow.add_condition(:check_duplicate, fn result ->
      case result do
        {:exact_duplicate, _} -> :skip_processing
        {:possible_duplicate, _} -> :deep_check
        :unique -> :full_processing
      end
    end)
    |> Workflow.add(
        :deep_dedup,
        Workers.DeepDeduplication.new(%{job_id: job_id}),
        condition: :deep_check
      )
    |> Workflow.add(
        :full_process,
        Workers.FullJobProcessing.new(%{job_id: job_id}),
        condition: :full_processing
      )
  end
end
```

### Pattern 3: Retry with Backoff
```elixir
defmodule Hirehound.Workers.ExternalAPIWorker do
  use Oban.Worker,
    queue: :enrichment,
    max_attempts: 5
  
  # Exponential backoff: 1min, 5min, 25min, 2hr, 10hr
  @impl Oban.Worker
  def backoff(attempt) do
    :math.pow(5, attempt) |> trunc() |> :timer.minutes()
  end
  
  @impl Oban.Worker
  def perform(%Job{attempt: attempt} = job) when attempt > 1 do
    Logger.info("Retry attempt #{attempt} for job #{job.id}")
    perform(job)
  end
  
  def perform(%Job{args: %{"url" => url}}) do
    case HTTPoison.get(url) do
      {:ok, %{status_code: 200, body: body}} -> 
        process_response(body)
        
      {:ok, %{status_code: 429}} ->
        # Rate limited - will retry with backoff
        {:error, :rate_limited}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

## Monitoring & Observability

### Metrics to Track
```elixir
defmodule Hirehound.Metrics.Workers do
  use Prometheus.Metric
  
  def setup do
    # Job processing metrics
    Counter.declare(
      name: :oban_jobs_processed_total,
      help: "Total number of jobs processed",
      labels: [:queue, :worker, :status]
    )
    
    Histogram.declare(
      name: :oban_job_duration_seconds,
      help: "Job execution duration",
      labels: [:queue, :worker],
      buckets: [0.1, 0.5, 1, 5, 10, 30, 60, 300]
    )
    
    Gauge.declare(
      name: :oban_queue_length,
      help: "Number of jobs in queue",
      labels: [:queue, :state]
    )
    
    # Workflow-specific metrics
    Counter.declare(
      name: :workflow_executions_total,
      help: "Total workflow executions",
      labels: [:workflow_name, :status]
    )
  end
end
```

### Dashboard Requirements
- Queue depths and processing rates
- Worker success/failure rates
- Average job duration per queue
- Workflow completion rates
- Resource utilization (CPU, memory, DB connections)
- Dead letter queue monitoring
- Rate limit hit frequency

## Failure Handling

### Dead Letter Queue
```elixir
defmodule Hirehound.Workers.DeadLetterHandler do
  use Oban.Worker,
    queue: :critical,
    max_attempts: 1
  
  @impl Oban.Worker
  def perform(%Job{args: %{"failed_job" => failed_job, "reason" => reason}}) do
    # Log to monitoring service
    Logger.error("Job permanently failed", 
      job_id: failed_job["id"],
      worker: failed_job["worker"],
      reason: reason
    )
    
    # Store in dead letter table for manual review
    DeadLetter.insert(%{
      job_data: failed_job,
      failure_reason: reason,
      failed_at: DateTime.utc_now()
    })
    
    # Alert if critical job
    if failed_job["queue"] == "critical" do
      Alerting.send_alert(:critical_job_failure, failed_job)
    end
    
    :ok
  end
end
```

### Circuit Breaker Pattern
```elixir
defmodule Hirehound.Workers.CircuitBreakerWrapper do
  use Oban.Worker
  
  @impl Oban.Worker
  def perform(%Job{args: args} = job) do
    service = args["service"]
    
    case Fuse.ask(service, :sync) do
      :ok ->
        # Circuit closed, proceed
        do_work(job)
        
      :blown ->
        # Circuit open, fail fast
        Logger.warn("Circuit breaker open for #{service}")
        {:error, :circuit_open}
    end
  end
  
  defp do_work(job) do
    # Actual work
    case perform_external_call(job) do
      {:ok, result} ->
        Fuse.reset(job.args["service"])
        {:ok, result}
        
      {:error, reason} ->
        Fuse.melt(job.args["service"])
        {:error, reason}
    end
  end
end
```

## Scaling Considerations

### Horizontal Scaling
- Multiple Elixir nodes with Oban distributed mode
- Partition queues across nodes
- Use consistent hashing for job distribution

### Vertical Scaling
- Increase queue concurrency limits
- Add more worker processes per queue
- Optimize database connections

### Database Optimization
- Partition Oban jobs table by queue or date
- Regular vacuum and analyze
- Connection pooling tuning

## Summary

Our workflow orchestration strategy:

✅ **Oban Pro** for Elixir-native workflow engine
✅ **Queue-per-concern** for isolation and tuning
✅ **Sophisticated pipelines** for ingestion, deduplication, enrichment
✅ **RAG/vectorization** for semantic search
✅ **Comprehensive monitoring** and alerting
✅ **Resilient failure handling** with retries and circuit breakers

This architecture supports complex, multi-step processes while maintaining observability and reliability.
