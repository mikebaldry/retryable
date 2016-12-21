defmodule Retryable.WorkSupervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    supervise(
      [
        worker(Retryable.Work, [], [restart: :temporary])
      ],
      strategy: :simple_one_for_one
    )
  end

  def attempt(opts) do
    Supervisor.start_child(__MODULE__, [opts])
  end
end
