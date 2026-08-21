# Subscriptions

> Status: Design stage -- specification only. Subscription delivery depends on `xiom-websocket`.

## Transport-agnostic at the API layer

Subscriptions in `xiom-graphql` are **transport-agnostic at the API layer**. The GraphQL layer defines the event contract and the subscribe/next/complete protocol semantics; the WebSocket package carries the frames; and the application decides what event sources produce the payloads. The subscription engine never depends on the socket transport directly.

This separation follows the same ecosystem rule as the rest of the stack: `xiom-websocket` owns the transport primitives, while `xiom-graphql` owns only the GraphQL protocol. Either side can evolve without dragging the other along.

## Typed event streams

A subscription is modeled as an explicit, typed event stream. The contract is a structural interface, mirroring the resolver contract but producing a stream instead of a single value:

```xiom
pub interface Subscription[T] {
  fn subscribe(ctx: &GraphQLContext, args: Args) -> Result[EventStream[T], GraphQLError]
}
```

`subscribe` runs once per subscription operation, after the operation has been parsed and validated like any other. It returns either a typed `EventStream[T]` or a `GraphQLError`. Each event pulled from the stream is then executed against the subscription's selection set -- so subscription payloads are resolved through the same execution machinery as queries.

## The event lifecycle

1. **Subscribe** -- the client sends a subscription operation over the transport. After validation, the bound `Subscription` resolver produces an `EventStream[T]`.
2. **Next** -- as the underlying event source emits values, each value is resolved against the selection set and serialized into a GraphQL response frame.
3. **Complete** -- the stream ends (source closed, client unsubscribed, or error), and the transport bridge tears down the channel.

## The WebSocket bridge

`transport/websocket_bridge.xi` adapts the transport-agnostic stream to `xiom-websocket`. It maps GraphQL subscription protocol messages onto WebSocket frames and back, without the engine ever naming the socket. Because the engine only sees `EventStream[T]`, the same subscription definitions could in principle be carried over a different transport by supplying a different bridge.

## Where payloads come from

`xiom-graphql` deliberately does not own event sources. Rooms, presence, and pub/sub semantics live in packages like `xiom-realtime`. The subscription layer simply defines *what* the event contract is and *how* it is validated and serialized; the application wires a concrete source (a channel, a queue, a domain event bus) into the stream returned by `subscribe`.
