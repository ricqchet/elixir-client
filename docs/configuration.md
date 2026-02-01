# Configuration

This guide covers configuration patterns for the Ricqchet Elixir client.

## Client Configuration

### Basic Setup

Define a client module with your configuration:

```elixir
defmodule MyApp.Queue do
  use Ricqchet.Client,
    base_url: "https://your-ricqchet.fly.dev",
    api_key: {:system, "RICQCHET_API_KEY"},
    destination: "https://myapp.com/webhook"
end
```

### Configuration Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `base_url` | string | yes | Ricqchet server URL |
| `api_key` | string or tuple | yes | API key for authentication |
| `destination` | string | no | Default destination URL |
| `timeout` | integer | no | HTTP timeout in ms (default: 30000) |

### API Key Formats

Static string (not recommended for production):

```elixir
api_key: "rq_live_abc123"
```

Environment variable (recommended):

```elixir
api_key: {:system, "RICQCHET_API_KEY"}
```

The `{:system, "VAR"}` tuple resolves the environment variable at runtime, making it suitable for releases and containerized deployments.

### Multiple Clients

Define separate clients for different use cases:

```elixir
defmodule MyApp.UserNotifications do
  use Ricqchet.Client,
    base_url: "https://ricqchet.fly.dev",
    api_key: {:system, "RICQCHET_API_KEY"},
    destination: "https://myapp.com/webhooks/users"
end

defmodule MyApp.OrderEvents do
  use Ricqchet.Client,
    base_url: "https://ricqchet.fly.dev",
    api_key: {:system, "RICQCHET_API_KEY"},
    destination: "https://myapp.com/webhooks/orders"
end

defmodule MyApp.ExternalIntegrations do
  use Ricqchet.Client,
    base_url: "https://ricqchet.fly.dev",
    api_key: {:system, "RICQCHET_API_KEY"}
    # No default destination - always specify explicitly
end
```

## Publish Options

When publishing messages, you can specify various options:

```elixir
MyApp.Queue.publish(payload, opts)
```

### Available Options

| Option | Type | Description |
|--------|------|-------------|
| `delay` | string | Delay delivery (e.g., "30s", "5m", "1h") |
| `dedup_key` | string | Deduplication key |
| `dedup_ttl` | integer | Deduplication TTL in seconds |
| `retries` | integer | Max retry attempts |
| `batch_key` | string | Batch key for grouping |
| `batch_size` | integer | Max batch size |
| `batch_timeout` | integer | Batch timeout in seconds |
| `forward_headers` | map | Headers to forward |
| `content_type` | string | Content-Type header |
| `destination` | string | Override default destination |

### Delayed Delivery

Schedule messages for future delivery:

```elixir
# Send in 5 minutes
MyApp.Queue.publish(%{event: "reminder"}, delay: "5m")

# Send in 1 hour
MyApp.Queue.publish(%{event: "follow_up"}, delay: "1h")

# Send in 30 seconds
MyApp.Queue.publish(%{event: "retry"}, delay: "30s")
```

### Deduplication

Prevent duplicate message processing:

```elixir
# Same key within TTL window is rejected
MyApp.Queue.publish(
  %{event: "order.created", order_id: 123},
  dedup_key: "order-123-created",
  dedup_ttl: 3600  # 1 hour
)
```

### Batching

Group multiple messages into a single delivery:

```elixir
# First message sets batch parameters
MyApp.Queue.publish(
  %{event: "page_view", page: "/home"},
  batch_key: "user-456-events",
  batch_size: 100,
  batch_timeout: 30
)

# Subsequent messages join the batch
MyApp.Queue.publish(
  %{event: "page_view", page: "/products"},
  batch_key: "user-456-events"
)
```

### Forward Headers

Pass custom headers to the destination:

```elixir
MyApp.Queue.publish(
  %{event: "notification"},
  forward_headers: %{
    "X-Correlation-Id" => "abc-123",
    "X-Source" => "my-service"
  }
)
```

### Custom Retries

Control retry behavior:

```elixir
# More retries for critical messages
MyApp.Queue.publish(
  %{event: "payment.processed"},
  retries: 10
)

# No retries for non-critical notifications
MyApp.Queue.publish(
  %{event: "analytics.pageview"},
  retries: 0
)
```

## Environment-Based Configuration

### Development

```elixir
# config/dev.exs
config :my_app,
  ricqchet_base_url: "http://localhost:4000"
```

```elixir
defmodule MyApp.Queue do
  use Ricqchet.Client,
    base_url: Application.compile_env!(:my_app, :ricqchet_base_url),
    api_key: {:system, "RICQCHET_API_KEY"},
    destination: "https://myapp.ngrok.io/webhook"
end
```

### Test

```elixir
# config/test.exs
config :ricqchet, adapter: Ricqchet.Adapters.Test
```

### Production

```elixir
# config/runtime.exs
config :my_app,
  ricqchet_base_url: System.get_env("RICQCHET_URL") || "https://ricqchet.fly.dev"
```

## Adapter Configuration

The client uses adapters for HTTP communication and testing.

### Default HTTP Adapter

```elixir
# No configuration needed - uses Ricqchet.Client.HTTP by default
```

### Test Adapter

```elixir
# config/test.exs
config :ricqchet, adapter: Ricqchet.Adapters.Test
```

### Custom Adapter

Implement the `Ricqchet.Client.Adapter` behaviour:

```elixir
defmodule MyApp.CustomAdapter do
  @behaviour Ricqchet.Client.Adapter

  @impl true
  def publish(config, destination, payload, opts) do
    # Custom implementation
  end

  @impl true
  def publish_fan_out(config, destinations, payload, opts) do
    # Custom implementation
  end

  @impl true
  def get_message(config, message_id) do
    # Custom implementation
  end

  @impl true
  def cancel_message(config, message_id) do
    # Custom implementation
  end

  @impl true
  def get_signing_secret(config) do
    # Custom implementation
  end
end
```

Configure it:

```elixir
config :ricqchet, adapter: MyApp.CustomAdapter
```

## Verification Configuration

### Basic Setup

```elixir
defmodule MyApp.RicqchetWebhook do
  use Ricqchet.Verification,
    signing_secret: {:system, "RICQCHET_SIGNING_SECRET"}
end
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `signing_secret` | string or tuple | required | Secret for HMAC verification |
| `max_age` | integer | 300 | Maximum signature age in seconds |

### Custom Max Age

For high-latency environments:

```elixir
defmodule MyApp.RicqchetWebhook do
  use Ricqchet.Verification,
    signing_secret: {:system, "RICQCHET_SIGNING_SECRET"},
    max_age: 600  # 10 minutes
end
```

## Inspecting Configuration

Access resolved configuration at runtime:

```elixir
# Client configuration
config = MyApp.Queue.config()
# %{base_url: "...", api_key: "...", destination: "...", timeout: 30000}

# Verification configuration
config = MyApp.RicqchetWebhook.config()
# %{signing_secret: "...", max_age: 300}
```
