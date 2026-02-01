# Webhook Verification

This guide covers verifying webhook signatures from Ricqchet deliveries in your Phoenix application.

## Overview

When Ricqchet delivers a message to your endpoint, it includes an HMAC signature in the `X-Ricqchet-Signature` header. Verifying this signature ensures:

1. The request actually came from Ricqchet
2. The payload hasn't been tampered with
3. The request isn't a replay attack (timestamp validation)

## Setup

### Define a Verification Module

Create a module that encapsulates your verification configuration:

```elixir
defmodule MyApp.RicqchetWebhook do
  use Ricqchet.Verification,
    signing_secret: {:system, "RICQCHET_SIGNING_SECRET"},
    max_age: 300  # 5 minutes (default)
end
```

The signing secret can be:
- A string: `signing_secret: "your-secret"`
- An environment variable: `signing_secret: {:system, "ENV_VAR"}`

### Get Your Signing Secret

Retrieve your signing secret using your Ricqchet client:

```elixir
{:ok, secret} = MyApp.Queue.get_signing_secret()
```

Store this in your environment variables (never commit secrets to your repository).

## Phoenix Integration

### Cache Raw Body

Signature verification requires the raw request body. By default, Phoenix parses the body and discards the raw bytes. You need to cache it:

```elixir
# lib/my_app_web/endpoint.ex
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app

  # Add a custom body reader for webhook routes
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    body_reader: {MyAppWeb.CacheBodyReader, :read_body, []},
    json_decoder: Phoenix.json_library()

  # ... rest of endpoint config
end
```

Create the body reader:

```elixir
# lib/my_app_web/cache_body_reader.ex
defmodule MyAppWeb.CacheBodyReader do
  @moduledoc """
  Caches the raw request body for signature verification.
  """

  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = Plug.Conn.assign(conn, :raw_body, body)
    {:ok, body, conn}
  end
end
```

### Controller Implementation

```elixir
defmodule MyAppWeb.WebhookController do
  use MyAppWeb, :controller

  def ricqchet(conn, params) do
    case MyApp.RicqchetWebhook.verify(conn) do
      {:ok, metadata} ->
        handle_delivery(conn, params, metadata)

      {:error, :missing_signature} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Missing signature"})

      {:error, :invalid_signature} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid signature"})

      {:error, :signature_expired} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Signature expired"})
    end
  end

  defp handle_delivery(conn, params, metadata) do
    # metadata contains: message_id, batch_id, attempt
    Logger.info("Processing delivery",
      message_id: metadata.message_id,
      attempt: metadata.attempt
    )

    # Process the webhook payload
    case process_event(params) do
      :ok ->
        json(conn, %{received: true})

      {:error, reason} ->
        # Return 500 to trigger retry
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: reason})
    end
  end

  defp process_event(%{"event" => "order.created"} = payload) do
    # Handle order created event
    :ok
  end

  defp process_event(_payload) do
    # Unknown event type
    :ok
  end
end
```

### Router Setup

```elixir
# lib/my_app_web/router.ex
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :webhook do
    plug :accepts, ["json"]
  end

  scope "/webhooks", MyAppWeb do
    pipe_through :webhook

    post "/ricqchet", WebhookController, :ricqchet
  end
end
```

## Verification Module API

### `verify/1`

Verifies the signature on a Plug.Conn:

```elixir
case MyApp.RicqchetWebhook.verify(conn) do
  {:ok, metadata} ->
    # metadata.message_id - Unique message ID
    # metadata.batch_id - Batch ID (if batched)
    # metadata.attempt - Delivery attempt number
    :ok

  {:error, reason} ->
    # :missing_signature - No signature header
    # :invalid_format - Malformed signature header
    # :invalid_signature - Signature doesn't match
    # :signature_expired - Timestamp too old
    :error
end
```

### `config/0`

Returns the resolved configuration:

```elixir
config = MyApp.RicqchetWebhook.config()
# %{signing_secret: "...", max_age: 300}
```

## Standalone Verification

If you don't have a full Plug.Conn (e.g., in a Lambda function), use `verify_payload/4`:

```elixir
signature_header = "t=1234567890,v1=abc123..."
raw_body = ~s({"event": "test"})
signing_secret = System.get_env("RICQCHET_SIGNING_SECRET")

case Ricqchet.Verification.verify_payload(
  signature_header,
  raw_body,
  signing_secret,
  max_age: 300
) do
  {:ok, timestamp} ->
    # Valid signature, timestamp is the Unix timestamp from the header
    :ok

  {:error, reason} ->
    :error
end
```

## Signature Format

The `X-Ricqchet-Signature` header has the format:

```
t=<timestamp>,v1=<signature>
```

Where:
- `timestamp` - Unix timestamp when the signature was created
- `signature` - HMAC-SHA256 of `<timestamp>.<raw_body>` using your signing secret

Example:

```
X-Ricqchet-Signature: t=1609459200,v1=5d41402abc4b2a76b9719d911017c592
```

## Idempotency

Your webhook endpoint may receive the same message multiple times due to:

- Network timeouts after successful processing
- Ricqchet retrying after an error response
- Duplicate delivery edge cases

Always implement idempotent handling:

```elixir
defp handle_delivery(conn, params, metadata) do
  message_id = metadata.message_id

  case MyApp.WebhookLog.record_if_new(message_id) do
    {:ok, _log} ->
      # First time seeing this message
      process_event(params)
      json(conn, %{received: true})

    {:error, :already_processed} ->
      # Already processed - return success without reprocessing
      json(conn, %{received: true, duplicate: true})
  end
end
```

## Handling Batched Messages

When messages are batched, the payload is a JSON array:

```elixir
defp handle_delivery(conn, params, metadata) do
  messages = if is_list(params), do: params, else: [params]

  Enum.each(messages, &process_event/1)

  json(conn, %{received: true, count: length(messages)})
end
```

## Troubleshooting

### "Missing signature" Error

Ensure the request has the `X-Ricqchet-Signature` header. Check your load balancer isn't stripping headers.

### "Invalid signature" Error

1. Verify you're using the correct signing secret
2. Ensure the raw body is cached before parsing (see Setup)
3. Check that no middleware is modifying the request body

### "Signature expired" Error

The request timestamp is older than `max_age` (default 300 seconds). This usually indicates:

1. Clock skew between servers - ensure NTP is configured
2. Replay attack attempt
3. Delayed request processing

Increase `max_age` if legitimate requests are being rejected:

```elixir
use Ricqchet.Verification,
  signing_secret: {:system, "RICQCHET_SIGNING_SECRET"},
  max_age: 600  # 10 minutes
```

### Debugging

Log the signature verification process:

```elixir
def ricqchet(conn, params) do
  signature = Plug.Conn.get_req_header(conn, "x-ricqchet-signature")
  Logger.debug("Signature header: #{inspect(signature)}")

  raw_body = conn.assigns[:raw_body]
  Logger.debug("Raw body length: #{byte_size(raw_body || "")}")

  # Continue with verification...
end
```
