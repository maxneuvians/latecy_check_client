defmodule LatencyCheckClient do
  use GenServer

  @cnc_url "http://localhost:4000"

  def start_link() do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    %{"query" => ip, "countryCode" => countryCode} = 
      HTTPoison.get!("http://ip-api.com/json")
      |> Map.get(:body)
      |> Poison.decode!

    [node, cookie] = 
      HTTPoison.get!(@cnc_url <> "/info")
      |> Map.get(:body)
      |> String.split("|")

    node = String.to_atom(node)
    cookie = String.to_atom(cookie)

    Node.start(:"#{countryCode}@#{ip}")
    Node.set_cookie(cookie)
    Node.connect(node)

    GenServer.call({LatencyCheck.CnC, node}, {:register, {Node.self(), ip, countryCode}})
    {:ok, %{node: node}}
  end

  def handle_cast({:query, url, id}, state) do
    time_query(url, id)
    {:noreply, state}
  end

  def handle_cast({:send, id, time}, state) do
    GenServer.cast({LatencyCheck.CnC, state[:node]}, {:result, {id, time, Node.self()}})
    {:noreply, state}
  end

  defp run_query(""), do: :error
  defp run_query(url) do
   case HTTPoison.get(url) do
     {:ok, %{status_code: 200}} -> :ok
     {:ok, %{status_code: 301}} -> :ok
     {:ok, %{status_code: 302}} -> :ok
     _ -> :error
   end
  end

  def time_query(url, id) do
    case :timer.tc(fn -> run_query(url) end) do
      {time, :ok} -> 
        time =
          time 
          |> Kernel./(1_000_000)
        GenServer.cast(__MODULE__, {:send, id, time})
      {time, :error} -> :error
    end
  end
end
