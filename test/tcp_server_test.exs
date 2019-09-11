defmodule TCPServerTest do
  use ExUnit.Case

  @user_port Application.get_env(:server, :ports)[:user]
  @event_port Application.get_env(:server, :ports)[:event_source]
  @ip {127, 0, 0, 1}

  describe "The TCP server" do
    test "allows clients to connect on both available ports" do
      inactive_port = 5000
      # Connect 2 user clients and 1 event client
      assert {:ok, u1} = :gen_tcp.connect(@ip, @user_port, [:binary, packet: 0, active: false])
      assert {:ok, u2} = :gen_tcp.connect(@ip, @user_port, [:binary, packet: 0, active: false])
      assert {:ok, evt} = :gen_tcp.connect(@ip, @event_port, [:binary, packet: 0])
      assert {:error, _} = :gen_tcp.connect(@ip, inactive_port, [:binary, {:packet, 0}])

      for client <- [u1, u2, evt] do
        :ok = :gen_tcp.close(client)
      end
    end
  end
end
