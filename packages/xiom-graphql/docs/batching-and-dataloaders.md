# Batching and DataLoaders

> Status: Design stage -- specification only.

## The N+1 problem

GraphQL's flexibility makes the N+1 query problem a real, recurring production concern. Consider a query that fetches a list of posts and, for each post, its author:

```graphql
query {
  posts {          # 1 query to load N posts
    title
    author {       # N queries, one per post, to load each author
      name
    }
  }
}
```

Resolved naively, the `author` field runs once per post -- N+1 round trips to the data source for a single request. As lists nest, the multiplication compounds. Because GraphQL lets clients shape arbitrary selections, this cannot be fixed by hand-tuning one query; it needs a systematic batching mechanism.

## First-class batching, not convention

`xiom.graphql` treats batching as **first-class** rather than leaving it to convention. It exposes an explicit `DataLoader` abstraction so resolver-side fetches can be collected and dispatched together. The package documents batching as the *default recommendation* for nested fields, not an optional optimization.

```xiom
pub interface DataLoader[K, V] {
  fn load(key: K) -> Result[V, GraphQLError]
  fn load_many(keys: Vec[K]) -> Result[Vec[V], GraphQLError]
}
```

## How it works

A `DataLoader` is created from a user-supplied batch function:

```xiom
BatchFn[K, V] = fn(keys: Vec[K]) -> Result[Vec[V], GraphQLError]
```

During a resolution tick, individual `load(key)` calls do not immediately hit the data source. Instead the loader **collects** the requested keys, then dispatches a single `BatchFn` call with all of them at once, and distributes the results back to each caller. In the posts/authors example, every `author` resolver calls `load(authorId)`, and the loader turns N individual loads into one batched fetch of N author IDs.

## Per-request caching

Loaders live on the request-scoped `GraphQLContext` (see `context.md`). This gives two properties:

1. **Caching** -- within a single request, loading the same key twice returns the cached value instead of re-fetching. If two posts share an author, that author is fetched once.
2. **Isolation** -- because loaders are scoped to the context, their caches clear automatically at the end of each request. There is no cross-request cache to invalidate and no stale-data hazard between clients.

Resolvers reach their loaders through the context:

```xiom
let authors = ctx.loader[Int, Author]("authorById")?
let author  = authors.load(post.author_id)?
```

## Ownership-safe by design

The loader interface is designed to be ownership-safe: caches are owned by the per-request context and never shared mutably across requests. Batching therefore improves performance without introducing shared-mutable-state hazards, keeping it consistent with XIOM's safety model.
