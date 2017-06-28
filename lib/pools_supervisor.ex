defmodule Retryable.PoolsSupervisor do
  use Supervisor

  def start_link do
    {:ok, pid} = Supervisor.start_link(__MODULE__, [], name: __MODULE__)

    create_pool(DefaultPool, 10)

    {:ok, pid}
  end

  def init([]) do
    supervise(
      [
        supervisor(Retryable.PoolSupervisor, [])
      ],
      strategy: :simple_one_for_one
    )
  end

  def create_pool(name, max_concurrent_jobs) do
    opts = [
      name: name,
      max_concurrent_jobs: max_concurrent_jobs
    ]

    Supervisor.start_child(__MODULE__, [opts])
  end

  def enqueue(pool_name, work) do
    pool_manager_name = Module.concat([Retryable.WorkManager, pool_name])

    unless Process.whereis(pool_manager_name) do
      raise "The pool '#{inspect pool_name}' does not exist"
    end

    GenServer.cast(pool_manager_name, {:enqueue, work})
  end
end
