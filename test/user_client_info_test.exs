defmodule UserClientInfoTest do
  use ExUnit.Case

  @user_port Application.get_env(:server, :ports)[:user]
  @ip {127, 0, 0, 1}

  setup context do
    u1_id = 65
    u2_id = 11

    # Connect 2 clients
    {:ok, u1} = :gen_tcp.connect(@ip, @user_port, [:binary, packet: 0])
    {:ok, u2} = :gen_tcp.connect(@ip, @user_port, [:binary, packet: 0])

    initialize_state? = Map.get(context, :initialize_state?, true)

    initial_state =
      if initialize_state? do
        %{
          sockets: %{u1_id => u1, u2_id => u2},
          followers: %{u2_id => [u1_id]}
        }
      else
        %{
          sockets: %{},
          followers: %{}
        }
      end

    {:ok, pid} = GenServer.start_link(UserClientInfo, initial_state, [name: :user_client_test_genserver])

    {:ok, pid: pid, u1: u1, u2: u2, u1_id: u1_id, u2_id: u2_id, initial_state: initial_state}
  end

  defp disconnect_clients(clients) do
    for client <- clients do
      :ok = :gen_tcp.close(client)
    end
  end

  describe "add_client" do
    test "adds a new client to test genserver state", %{pid: pid, u1: u1, u2: u2, initial_state: initial_state} do
      # Connect a 3rd client
      u3_id = 42
      {:ok, u3} = :gen_tcp.connect(@ip, @user_port, [:binary, packet: 0])

      assert :sys.get_state(pid) == initial_state

      GenServer.call(pid, {:add_client, u3, u3_id})

      assert :sys.get_state(pid) == put_in(initial_state, [:sockets, u3_id], u3)

      disconnect_clients([u1, u2, u3])
    end
  end

  describe "get_client" do
    test "returns the client socket corresponding to a given user id", %{pid: pid, u1: u1, u2: u2, u1_id: u1_id} do
      assert u1 == GenServer.call(pid, {:get_client, u1_id})

      disconnect_clients([u1, u2])
    end

    @tag initialize_state?: false
    test "returns nil if the user id is not in the state", %{pid: pid, u1: u1, u2: u2, u1_id: u1_id} do
      assert nil == GenServer.call(pid, {:get_client, u1_id})

      disconnect_clients([u1, u2])
    end
  end

  describe "get_all_clients" do
    test "returns a list with all connected client sockets", %{pid: pid, u1: u1, u2: u2} do
      assert [u1, u2] == GenServer.call(pid, :get_all_clients)

      disconnect_clients([u1, u2])
    end

    @tag initialize_state?: false
    test "returns an empty list in case that are no clients", %{pid: pid, u1: u1, u2: u2} do
      assert [] == GenServer.call(pid, :get_all_clients)

      disconnect_clients([u1, u2])
    end
  end

  describe "add_follower" do
    test "adds a new follower for a given user id", %{pid: pid, u1: u1, u2: u2, u2_id: u2_id, initial_state: initial_state} do
      # Connect a 3rd client
      u3_id = 42
      {:ok, u3} = :gen_tcp.connect(@ip, @user_port, [:binary, packet: 0])

      assert :sys.get_state(pid) == initial_state
      current_followers = get_in(initial_state, [:followers, u2_id])

      GenServer.call(pid, {:add_follower, u2_id, u3_id})

      assert :sys.get_state(pid) == put_in(initial_state, [:followers, u2_id], [u3_id | current_followers])

      disconnect_clients([u1, u2, u3])
    end
  end

  describe "remove_follower" do
    test "removes a follower for a given user id", %{pid: pid, u1: u1, u2: u2, u1_id: u1_id, u2_id: u2_id, initial_state: initial_state} do

      assert :sys.get_state(pid) == initial_state
      current_followers = get_in(initial_state, [:followers, u2_id])

      GenServer.call(pid, {:remove_follower, u2_id, u1_id})

      assert :sys.get_state(pid) == put_in(initial_state, [:followers, u2_id], [])

      disconnect_clients([u1, u2])
    end
  end

  describe "get_followers" do
    test "returns a list with the ids of all followers of a given user", %{pid: pid, u1: u1, u2: u2, u1_id: u1_id, u2_id: u2_id} do
      assert [u1_id] == GenServer.call(pid, {:get_followers, u2_id})

      disconnect_clients([u1, u2])
    end

    @tag initialize_state?: false
    test "returns an empty list in case that are no followers", %{pid: pid, u1: u1, u2: u2, u2_id: u2_id} do
      assert [] == GenServer.call(pid, {:get_followers, u2_id})

      disconnect_clients([u1, u2])
    end
  end
end
