defmodule Acceptor do
  use Supervisor, type: :supervisor

  @type port_number :: pos_integer()
  @type socket :: port()

  @spec start_link(any()) :: Supervisor.on_start()
  def start_link(_), do: Supervisor.start_link(__MODULE__, nil)

  @spec port() :: port_number()
  def port(), do: 6889

  @spec socket_options() :: list()
  def socket_options(), do: [:binary, active: false, reuseaddr: true]

  @spec ip() :: binary
  def ip() do
    :inet.getif()
    |> elem(1)
    |> hd()
    |> elem(0)
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  @spec recv(socket()) :: DynamicSupervisor.on_start_child()
  def recv(client) do
    Task.Supervisor.start_child(__MODULE__.Handshakes, Handshake, :recv, [client])
  end

  @spec send(Peer.peer(), Torrent.hash()) :: DynamicSupervisor.on_start_child()
  def send(peer, hash) do
    Task.Supervisor.start_child(__MODULE__.Handshakes, Handshake, :send, [peer, hash])
  end

  def init(_) do
    [
      __MODULE__.BlackList,
      __MODULE__.Pool,
      {
        Task.Supervisor,
        name: __MODULE__.Handshakes, strategy: :one_for_one, max_restarts: 0
      },
      __MODULE__.Listen
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end
end
