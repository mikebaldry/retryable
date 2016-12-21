# Retryable

Allows you to run some code and handle any timeouts or errors, with custom retry logic.

I built this because the few packages out there don't give you such fine-grained
control of how long to wait for retries in different cases, for instance, if you hit an
API and it told you your rate limit had been hit and to retry in 38 seconds, any other
retry package only lets you retry in a fixed preconfigured time period with backoffs, etc.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `retryable` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:retryable, "~> 0.1.0"}]
    end
    ```

  2. Ensure `retryable` is started before your application:

    ```elixir
    def application do
      [applications: [:retryable]]
    end
    ```

## Usage

The nicest way to use is via the macro `Retryable.attempt`:

```elixir
require Retryable

attempt = Retryable.attempt do
  MyWebService.flakey_request # result is caught below
catch
  {:timeout, 5_000} -> # {:timeout, _} is handled by Retryable and called if exceeded and the work stopped.
    if attempts == 5 do
      {:error, :timed_out_after_5_attempts}
    else
      # retry in 2,4,8,16 seconds, with 100ms of jitter
      {:retry, Retryable.jitter(100) |> Retryable.exponential_backoff(attempts)}
    end
  {:ok, result} -> :ok
  {:error, e} -> # {:error, _} is also called if the work crashes the process, etc.
    if attempts == 3 do
      {:error, :errored}
    else
      {:retry, 500} # retry errors in 500ms
    end
end

receive do
  {^attempt, {:ok, result}} -> # result == return value of MyWebService.flakey_request
  {^attempt, {:error, e}} -> # in this example, result == :errored or :timed_out_after_5_attempts
end
```

You can also call it less magically via the function `Retryable.attempt_work`:

```elixir
{:ok, attempt_pid} = Retryable.attempt_work(
  retry_strategy: fn (attempts, result) -> {:retry, 500} end,
  retryable: fn -> MyWebService.flakey_request end,
  notify: self, # optional, process will receive {attempt_pid, {:ok/:error, result}}
  timeout_ms: 5_000 # optional, if not specified, nothing will timeout, except your receive if waiting for message
)
```

All work is carried out in a separate supervision tree and you should never see a failure directly affect your own process.
