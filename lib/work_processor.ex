defmodule Retryable.WorkProcessor do
  use GenServer

  alias Retryable.Work

  def start_link(manager) do
    GenServer.start_link(__MODULE__, manager, [])
  end

  def init(manager) do
    send(self(), :loop)

    {:ok, manager}
  end

  def handle_info(:loop, manager) do
    case GenServer.call(manager, :retrieve_work) do
      {:job, work} -> process_work(work)
      :nothing -> :timer.sleep(10)
    end

    send(self(), :loop)

    {:noreply, manager}
  end

  defp process_work(work) do
    work
    |> Work.started
    |> Work.process
  end
end