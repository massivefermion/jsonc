defmodule JSONC.Decoder do
  import JSONC.Parser

  def decode!(content) when is_binary(content) do
    case decode(content) do
      {:ok, result} -> result
      {:error, reason} -> raise reason
    end
  end

  def decode(content) when is_binary(content) do
    case parse(content) do
      {:ok, %{type: :root, value: value}} ->
        case gather_value(value) do
          {:error, reason} ->
            {:error, reason}

          result ->
            {:ok, result}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp gather_value(value) when is_map(value) do
    case value do
      %{type: :object, value: object_node} ->
        gather_object(object_node) |> Map.new()

      %{type: :array, value: array_node} ->
        gather_array(array_node)

      %{value: value} ->
        value

      %{type: nil} ->
        nil
    end
  end

  defp gather_object(node) when is_map(node) do
    node |> Enum.map(fn {k, v} -> {k, gather_value(v)} end)
  end

  defp gather_array(node) when is_list(node) do
    node |> Enum.map(fn v -> gather_value(v) end)
  end
end
