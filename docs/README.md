# Hirehound Documentation

Welcome to the Hirehound documentation! This folder contains design documents, research, and planning materials for building a job aggregation platform for the South African market.

## Documentation Structure

### 📖 [00 - Glossary](./00-glossary.md)
**Definitions of key terms and concepts** used throughout the documentation.

**Start here if you encounter unfamiliar terms!**

**Key Terms Defined:**
- **Cluster** - Group of duplicate entities
- **Canonical** - Primary entity in a cluster
- **Blocking** - Performance optimization for deduplication
- **Enrichment** - Adding external data
- **Vectorization** - Text to embeddings for semantic search
- **Workflow** - Multi-step background process
- **Plus 40+ more terms...**

### 📋 [01 - Project Overview](./01-project-overview.md)

High-level vision, objectives, and technology choices. Start here to understand what Hirehound is and why we're building it.

**Key Topics:**

- Project vision and goals
- Technology stack rationale
- Target job boards
- Core challenges
- Success metrics

### 📊 [02 - Job Posting Standards](./02-job-posting-standards.md)

Research on industry standards for job postings and our proposed unified schema, **including organizations as first-class entities**.

**Key Topics:**

- Schema.org JobPosting standard
- **Organization schema (first-class entities)**
- South African job board analysis
- Recommended unified schema design
- Data normalization strategies
- Field-by-field documentation

### 🔍 [03 - Deduplication Strategy](./03-deduplication-strategy.md)

Comprehensive approach to identifying and handling duplicates for **both job postings AND organizations**.

**Key Topics:**

- **Dual deduplication (jobs + organizations)**
- Types of duplicates (exact, near, fuzzy)
- Multi-stage detection pipeline
- **Organization-specific deduplication**
- Database schema for duplicates
- Clustering algorithms
- **Workflow orchestration**
- Performance optimization
- Edge cases and solutions

### 🚀 [04 - Next Steps](./04-next-steps.md)

Detailed implementation roadmap with phases, tasks, and deliverables.

**Key Topics:**

- 6-phase implementation plan
- Week-by-week task breakdown
- Success criteria per phase
- Open questions for discussion
- Learning topics and resources

### ⚙️ [05 - Workflow Orchestration](./05-workflow-orchestration.md)

**Sophisticated background job and workflow orchestration** for all async processing needs.

**Key Topics:**

- **Oban Pro workflow engine**
- Job ingestion pipeline
- Organization enrichment pipeline
- **Deduplication workflows**
- **Spam filtering workflows**
- **RAG/vectorization for semantic search**
- Batch processing patterns
- Monitoring & observability
- Failure handling & resilience

### 🛠️ [06 - Development Practices](./06-development-practices.md)

**How we build software** - Elixir-native, iterative, REPL-first development.

**Key Topics:**

- **Standard library choices** (Req, Oban/Oban Pro)
- **IEx-first workflow** (REPL before UI)
- **Behaviour-based architecture** (JobBoard behaviour)
- **URL-based auto-routing** (paste any URL, system picks scraper)
- **Iterative development** (manual → test → automate)
- Code organization patterns
- Testing philosophy
- Migration strategies

### 🏗️ [07 - Scraper Architecture](./07-scraper-architecture.md)

**Quick reference** for the URL-based scraper routing system.

**Key Topics:**

- **Visual architecture diagram**
- **When to use direct calls vs auto-routing**
- **Component breakdown** (Behaviour, Registry, Scraper)
- **Development checklist** for new scrapers
- **Example IEx session** walkthrough
- **Quick reference table**

## Quick Start Guide

If you're new to the project, we recommend reading in this order:

1. **[Glossary](./00-glossary.md)** - Learn key terminology (reference as needed)
2. **[Project Overview](./01-project-overview.md)** - Understand the "why"
3. **[Development Practices](./06-development-practices.md)** - See how we build (IEx-first!)
4. **[Scraper Architecture](./07-scraper-architecture.md)** - Quick reference for scraping
5. **[Job Posting Standards](./02-job-posting-standards.md)** - Learn the data model
6. **[Deduplication Strategy](./03-deduplication-strategy.md)** - Understand the core challenge
7. **[Workflow Orchestration](./05-workflow-orchestration.md)** - See background job architecture
8. **[Next Steps](./04-next-steps.md)** - Detailed implementation roadmap

## Current Phase

**Status:** 🔷 Design & Research Phase

We are currently in the exploratory design phase, focusing on:

- Finalizing the data schema
- Researching deduplication approaches
- Planning the scraping architecture
- No code implementation yet

**Next Milestone:** Complete Phase 1 (Foundation) - Database schema and data models

## Key Design Decisions

### ✅ Decided

- **Database:** PostgreSQL with JSONB for flexibility
- **Backend:** Elixir/Phoenix for concurrency and reliability
- **Deduplication:** Multi-stage pipeline (exact → near → fuzzy)
- **Schema:** Superset design accommodating all sources

### 🤔 Under Consideration

- Scraping frequency per source
- ML vs rule-based deduplication
- Historical data retention policy
- Frontend framework choices (React vs LiveView)

### ❓ Open Questions

- API vs scraping for LinkedIn
- Monetization strategy
- User authentication approach
- Multi-language support (English + Afrikaans)

## Contributing to Documentation

When adding or updating documentation:

1. **Use clear headers** - Help readers navigate
2. **Include examples** - Code, data, or scenarios
3. **Link between docs** - Create a connected web of information
4. **Update this README** - Keep the overview current
5. **Date major changes** - Add version history if needed

## Additional Resources

### External References

- [Schema.org JobPosting](https://schema.org/JobPosting)
- [Google for Jobs Guidelines](https://developers.google.com/search/docs/appearance/structured-data/job-posting)
- [Elixir Forum: Web Scraping](https://elixirforum.com/t/web-scraping-in-elixir/)
- [PostgreSQL Full-Text Search](https://www.postgresql.org/docs/current/textsearch.html)

### Tools & Libraries

- [Floki](https://hex.pm/packages/floki) - HTML parsing
- [Crawly](https://hex.pm/packages/crawly) - Web scraping framework (Will try to manage without Crawly at first)
- [Oban](https://hex.pm/packages/oban) - Background jobs
- [Ecto](https://hex.pm/packages/ecto) - Database wrapper

## Feedback & Questions

This is a living document set. If you have:

- **Questions** about design decisions → Create a GitHub issue
- **Suggestions** for improvements → Open a PR with proposed changes
- **Found errors** or outdated info → Submit a correction

---

**Last Updated:** 2024
**Status:** Design Phase
**Version:** 0.1.0 (Pre-implementation)
