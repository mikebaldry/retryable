defmodule Retryable.PoolSupervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: Module.concat(__MODULE__, opts[:name]))
  end

  def init(name: name, max_concurrent_jobs: max_concurrent_jobs) do
    manager_name = Module.concat([Retryable.WorkManager, name])

    workers =
      (1..max_concurrent_jobs)
      |> Enum.map(fn (i) ->
        worker(Retryable.WorkProcessor, [manager_name], id: i)
      end)

    children = [
      worker(Retryable.WorkManager, [name])
    ] ++ workers

    supervise(children, strategy: :one_for_one)
  end
end
