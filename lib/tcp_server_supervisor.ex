defmodule TCPServer.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(_args) do
    children = [
      {Task.Supervisor, name: TCPServer.TaskSupervisor},
      TCPServer,
      UserClientInfo,
      Notifier
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
