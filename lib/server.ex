defmodule Server do
  use Application

  @impl true
  def start(_type, _args) do
    # Will start the TCPServer.Supervisor supervisor when `iex -S mix` is run
    TCPServer.Supervisor.start_link([])
  end
end
