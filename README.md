# Retryable

Allows you to run some code and handle any timeouts or errors, with custom retry logic, while limiting the total number of concurrent things being run via worker pools.

I built this because the few packages out there don't give you such fine-grained
control of how long to wait for retries in different cases, for instance, if you hit an
API and it told you your rate limit had been hit and to retry in 38 seconds, any other
retry package only lets you retry in a fixed preconfigured time period with backoffs, etc.

## Installation

If [available in Hex](https://hex.pm/packages/retryable), the package can be installed as:

1. Add `retryable` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:retryable, "~> 0.2.0"}]
end
```

2. Ensure `retryable` is started before your application:

```elixir
def application do
  [applications: [:retryable]]
end
```

## Usage

A default pool is provided, which has 10 workers. You can create your own pool during your apps initialisation:

```elixir
Retryable.create_pool(MyPool, 50)
```

You can use the familiar `call` or `cast`. If you use `call`, it will wait for a result and return it,
this could take a long time, depending on the size of the queue, how long the job takes and how many times it will retry. `cast` will run the work in the background and continue with your code.

Both functions take a list of options which can be any of the following:

- `work` - A function to call to carry out the work. This must return either `{:ok, result}` or `{:error, err}`. An exception being raising is considered `{:error, err}`.
- `when_complete` A function to call with the result when the work is completed. This allows you to asyncronously deal with the result, inline with the `cast`.
- `timeout` - The maximum number of milliseconds the `work` is allowed to take before it is considered to have timed out. This is optional, not passing it will mean no timeout.
- `on_success` - A function called when `work` returns `{:ok, result}`, with 2 arguments, `attempts` and `result`. Must return either `{:return, result}`, `{:fail, error}` or `{:retry, ms_to_retry_in}`. This is optional, the default is `fn (_, result) -> {:return, result} end`.
- `on_error` - A function called when `work` returns `{:error, error}` or raises, with 2 arguments, `attempts` and `error`. Must return either `{:return, result}`, `{:fail, error}` or `{:retry, ms_to_retry_in}`. This is optional, the default is `fn (_, error) -> {:fail, error} end`.
- `on_timeout` - A function called when `work` does't complete in `timeout` milliseconds, with 2 arguments, `attempts` and `:timeout`. Must return either `{:return, result}`, `{:fail, error}` or `{:retry, ms_to_retry_in}`. This is optional, the default is `fn (_, :timeout) -> {:fail, :timeout} end`

As you can see, this can be really simple:

```elixir
result = Retryable.call(
  timeout: 5000,
  work: fn -> SomeFlakeyWebService.call end
)
```

or more complicated:

```elixir
result = Retryable.call(
  timeout: 5000,
  work: fn -> SomeFlakeyWebService.call end,
  on_success: fn (_, %{data: data}) -> {:return, data} end,
  on_timeout: fn
    (attempts, _) when attempts < 5 ->
      # retry in 2,4,8,16 seconds, with 100ms of jitter
      {:retry, Retryable.jitter(100) |> Retryable.exponential_backoff(attempts)}
    (attempts, _) -> {:fail, :timeout}
  end,
  on_error: fn
    (_, :not_found) -> {:fail, :not_found}
    (attempts, _) when attempts < 10 -> {:retry, 100}
    (attempts, error) -> {:fail, error}
  end
)
```

All work is carried out in a separate supervision tree and you should never see a failure directly affect your own process.
