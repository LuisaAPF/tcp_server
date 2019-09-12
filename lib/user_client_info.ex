defmodule UserClientInfo do
  use GenServer

  @moduledoc """
  This module stores and manages information about the connected user clients.
  """

  def start_link(opts) do
    opts = [name: __MODULE__] |> Keyword.merge(opts)

    # Ex:
    # %{
    #   sockets: %{"10" => Port<0.26>, "89" => Port<0.27>},
    #   followers: %{"10" => ["50", "7", "89"]}
    # }
    initial_state = %{
      sockets: %{}, # Map id => socket
      followers: %{} # Map id => list of followers
    }

    GenServer.start_link(__MODULE__, initial_state, opts)
  end

  @impl true
  def init(initial_state) do
    {:ok, initial_state}
  end

  @doc """
  Adds a map of the form %{user_id => client} to state.sockets. Returns :ok.
  """
  @impl true
  def handle_call({:add_client, client, user_id}, _from, state) do
    new_state = put_in(state, [:sockets, user_id], client)

    {:reply, :ok, new_state}
  end

  @doc """
  Returns a client socket corresponding to user_id.
  """
  @impl true
  def handle_call({:get_client, user_id}, _from, state) do
    client = get_in(state, [:sockets, user_id])

    {:reply, client, state}
  end

  @doc """
  Returns a list with all client sockets.
  """
  @impl true
  def handle_call(:get_all_clients, _from, state) do
    clients = Enum.reduce(state.sockets, [], fn {_id, socket}, acc ->
      [socket | acc]
    end)

    {:reply, clients, state}
  end

  @doc """
  Adds a follower of user_id. Returns :ok.
  """
  @impl true
  def handle_call({:add_follower, user_id, follower_id}, _from, state) do
    followers = get_in(state, [:followers, user_id]) || []
    followers = [follower_id | followers]

    new_state = put_in(state, [:followers, user_id], followers)

    {:reply, :ok, new_state}
  end

  @doc """
  Removes a follower of user_id. Returns :ok.
  """
  @impl true
  def handle_call({:remove_follower, user_id, follower_id}, _from, state) do
    followers = get_in(state, [:followers, user_id]) || []
    followers = List.delete(followers, follower_id)

    new_state = put_in(state, [:followers, user_id], followers)

    {:reply, :ok, new_state}
  end

  @doc """
  Returns a list with a user's followers.
  """
  @impl true
  def handle_call({:get_followers, user_id}, _from, state) do
    followers = get_in(state, [:followers, user_id]) || []

    {:reply, followers, state}
  end

  @doc """
  Resets the genserver state to its initial value. Used in tests.
  """
  @impl true
  def handle_call(:empty_state, _from, _state) do
    new_state = %{
      sockets: %{},
      followers: %{}
    }

    {:reply, :ok, new_state}
  end
end
