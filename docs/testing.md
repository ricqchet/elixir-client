# Testing Guide

This guide covers testing strategies for applications using the Ricqchet client library.

## Setup

Configure the test adapter in `config/test.exs`:

```elixir
import Config

config :ricqchet, adapter: Ricqchet.Adapters.Test
```

This replaces the HTTP adapter with a test adapter that captures calls and allows assertions.

## Basic Assertions

Import `Ricqchet.Testing` in your test modules:

```elixir
defmodule MyApp.NotificationTest do
  use ExUnit.Case, async: true
  import Ricqchet.Testing

  test "publishes order confirmation" do
    order = %{id: 123, total: 99.99}

    {:ok, %{message_id: id}} = MyApp.Notifications.order_confirmed(order)

    assert is_binary(id)
    assert_published destination: "https://myapp.com/webhook",
                     payload: %{event: "order.confirmed", order_id: 123}
  end
end
```

### Available Assertions

#### `assert_published/1`

Asserts that a message was published. Accepts optional criteria:

```elixir
# Assert any publish occurred
assert_published()

# Assert destination
assert_published destination: "https://example.com"

# Assert payload (exact match)
assert_published payload: %{event: "user.created", user_id: 1}

# Assert publish options
assert_published delay: "5m"
assert_published dedup_key: "order-123"
assert_published retries: 5

# Combine criteria
assert_published destination: "https://example.com",
                 payload: %{event: "test"},
                 delay: "1h"
```

Returns the actual call details for further inspection:

```elixir
call = assert_published destination: "https://example.com"
assert call.opts[:delay] == "30s"
```

#### `refute_published/1`

Asserts that no message was published:

```elixir
test "does not publish when validation fails" do
  invalid_order = %{total: -10}

  {:error, _} = MyApp.Notifications.order_confirmed(invalid_order)

  refute_published()
end
```

#### `assert_fan_out/2`

Asserts a fan-out publish to multiple destinations:

```elixir
test "broadcasts to all subscribers" do
  destinations = [
    "https://service-a.example.com/hook",
    "https://service-b.example.com/hook"
  ]

  {:ok, _} = MyApp.Queue.publish_fan_out(destinations, %{event: "broadcast"})

  # Order doesn't matter
  assert_fan_out destinations
  assert_fan_out destinations, payload: %{event: "broadcast"}
end
```

#### `assert_get_message/2` and `assert_cancel_message/2`

Assert message management calls:

```elixir
test "checks message status" do
  message_id = "550e8400-e29b-41d4-a716-446655440000"

  MyApp.Queue.get_message(message_id)

  assert_get_message(message_id)
end

test "cancels pending message" do
  message_id = "550e8400-e29b-41d4-a716-446655440000"

  MyApp.Queue.cancel_message(message_id)

  assert_cancel_message(message_id)
end
```

## Stubbing Responses

Use `stub_response/3` to control what the test adapter returns:

```elixir
test "handles rate limiting" do
  stub_response(:publish, {:error, %Ricqchet.Error{type: :rate_limited}})

  result = MyApp.Queue.publish(%{event: "test"})

  assert {:error, %{type: :rate_limited}} = result
end

test "handles network errors" do
  stub_response(:publish, {:error, :network_error})

  result = MyApp.Queue.publish(%{event: "test"})

  assert {:error, :network_error} = result
end
```

### Conditional Stubs

Stub responses for specific destinations or message IDs:

```elixir
test "handles slow endpoint differently" do
  stub_response(:publish, {:error, :timeout},
    destination: "https://slow.example.com")

  # This fails
  assert {:error, :timeout} =
    MyApp.Queue.publish_to("https://slow.example.com", %{event: "test"})

  # This succeeds (different destination)
  assert {:ok, _} =
    MyApp.Queue.publish_to("https://fast.example.com", %{event: "test"})
end

test "handles missing message" do
  stub_response(:get_message, {:error, :not_found},
    message_id: "nonexistent")

  assert {:error, :not_found} = MyApp.Queue.get_message("nonexistent")
end
```

## Testing GenServers and Background Processes

When testing code that spawns processes (GenServers, Tasks, etc.), use global mode:

```elixir
defmodule MyApp.WorkerTest do
  use ExUnit.Case, async: false  # Required for global mode
  import Ricqchet.Testing

  setup do
    set_ricqchet_global()
    :ok
  end

  test "worker publishes on tick" do
    {:ok, worker} = MyApp.Worker.start_link()

    send(worker, :tick)

    # Give the worker time to process
    Process.sleep(50)

    assert_published destination: "https://example.com/events"
  end
end
```

**Important:** Tests using `set_ricqchet_global/0` must use `async: false` because they share global state.

## Debugging Tests

### Inspect All Calls

Use `get_ricqchet_calls/0` to see all recorded calls:

```elixir
test "debugging example" do
  MyApp.Queue.publish(%{event: "a"})
  MyApp.Queue.publish(%{event: "b"})

  calls = get_ricqchet_calls()

  IO.inspect(calls, label: "All Ricqchet calls")

  assert length(calls) == 2
end
```

### Reset State

Use `reset_ricqchet/0` in setup blocks for a clean slate:

```elixir
setup do
  reset_ricqchet()
  :ok
end
```

## Using Mox for Explicit Expectations

For more control, use Mox with the adapter behaviour:

### Setup

```elixir
# test/support/mocks.ex
Mox.defmock(Ricqchet.MockAdapter, for: Ricqchet.Client.Adapter)

# config/test.exs
config :ricqchet, adapter: Ricqchet.MockAdapter
```

### Usage

```elixir
defmodule MyApp.QueueMoxTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  test "with explicit expectations" do
    expect(Ricqchet.MockAdapter, :publish, fn _config, dest, payload, opts ->
      assert dest == "https://myapp.com/webhook"
      assert payload.event == "order.created"
      assert opts[:delay] == "5m"
      {:ok, %{message_id: "custom-id-123"}}
    end)

    result = MyApp.Queue.publish(%{event: "order.created"}, delay: "5m")

    assert {:ok, %{message_id: "custom-id-123"}} = result
  end

  test "verify call count" do
    expect(Ricqchet.MockAdapter, :publish, 2, fn _config, _dest, _payload, _opts ->
      {:ok, %{message_id: UUID.uuid4()}}
    end)

    MyApp.Queue.publish(%{event: "first"})
    MyApp.Queue.publish(%{event: "second"})

    # verify_on_exit! ensures exactly 2 calls were made
  end
end
```

## Integration Testing

For integration tests against a real Ricqchet server:

```elixir
# config/test.exs
if System.get_env("RICQCHET_INTEGRATION") do
  config :ricqchet, adapter: Ricqchet.Client.HTTP
end

# test/integration/ricqchet_test.exs
defmodule MyApp.RicqchetIntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  @tag :integration
  test "publishes to real server" do
    {:ok, %{message_id: id}} = MyApp.Queue.publish(%{event: "integration_test"})

    assert is_binary(id)

    # Verify message exists
    {:ok, message} = MyApp.Queue.get_message(id)
    assert message.status in ["pending", "dispatched", "delivered"]
  end
end
```

Run integration tests:

```bash
RICQCHET_INTEGRATION=1 mix test --only integration
```
