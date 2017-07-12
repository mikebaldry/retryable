defmodule Retryable do
  defmodule App do
    use Application

    def start(_type, _args) do
      import Supervisor.Spec, warn: false

      children = [
        supervisor(Retryable.PoolsSupervisor, []),
      ]

      opts = [strategy: :one_for_one, name: Retryable.Supervisor]
      Supervisor.start_link(children, opts)
    end
  end

  @doc """
    Create a pool of workers called `name`, with `max_concurrent_jobs` (defaults to 10) number of concurrent processes.
  """
  def create_pool(pool_name, max_concurrent_jobs \\ 10) do
    Retryable.PoolsSupervisor.create_pool(
      pool_name,
      max_concurrent_jobs
    )
  end

  @doc """
    Enqueues a new piece of work to be carried out, without waiting for it to complete.
    Returns the id of the work.
  """
  def cast(opts) when is_list(opts) do
    {pool_name, opts} = Keyword.pop_first(opts, :pool_name, DefaultPool)
    work = Retryable.Work.new(opts)
    cast(work, pool_name)
  end

  @doc """
    Enqueues a new piece of work to be carried out, without waiting for it to complete.
    Returns the id of the work.
  """
  def cast(work = %Retryable.Work{}, pool_name \\ DefaultPool) do
    Retryable.PoolsSupervisor.enqueue(pool_name, work)
    work.id
  end

  @doc """
    Enqueues a new piece of work to be carried out, and waits for it to complete, returning the result.
  """
  def call(opts) when is_list(opts) do
    {pool_name, opts} = Keyword.pop_first(opts, :pool_name, DefaultPool)
    work = Retryable.Work.new(opts)
    call(work, pool_name)
  end

  @doc """
    Enqueues a new piece of work to be carried out, and waits for it to complete.
    Returns the result.
  """
  def call(work = %Retryable.Work{}, pool_name \\ DefaultPool) do
    me = self()
    when_complete = fn (id, result) -> send(me, {id, result}) end

    id = cast(%{work | when_complete: when_complete}, pool_name)

    receive do
      {^id, result} -> result
    end
  end

  @doc """
    Adds jitter to a retry time so that many failing jobs won't all retry at
    the same time
  """
  def jitter(amount_ms), do: jitter(0, amount_ms)
  def jitter(value_ms, amount_ms) do
    value_ms + round(:rand.uniform * amount_ms)
  end

  @doc """
    Adds an exponential backoff to a retry time based on the number of attempts
  """
  def exponential_backoff(value_ms, attempts, exp_base \\ 2) do
    value_ms + round((:math.pow(exp_base, attempts) * 1000))
  end
end
