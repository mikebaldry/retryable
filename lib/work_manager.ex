defmodule Retryable.WorkManager do
  use GenServer
  require Logger

  def start_link(name) do
    GenServer.start_link(__MODULE__, name, name: Module.concat(__MODULE__, name))
  end

  def init(name) do
    {:ok, {name, :queue.new}}
  end

  def handle_cast({:enqueue, work}, {name, queue}) do
    Logger.info "[Retryable][#{work.id}] Work enqueued in #{inspect name}."

    work = Retryable.Work.enqueued(work)

    {:noreply, {name, :queue.in(work, queue)}}
  end

  def handle_call(:retrieve_work, _from, {name, queue}) do
    case :queue.out(queue) do
      {{:value, work}, queue} -> {:reply, {:job, work}, {name, queue}}
      {:empty, queue} -> {:reply, :nothing, {name, queue}}
    end
  end
end