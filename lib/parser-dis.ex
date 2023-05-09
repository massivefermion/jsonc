defmodule JSONC.ParserDis do
  @moduledoc false

  import JSONC.Tokenizer

  def parse!(content) when is_binary(content) do
    case parse(content) do
      {:ok, result} ->
        result

      {:error, reason} ->
        raise reason
    end
  end

  def parse(content) when is_binary(content) do
    parse_value({content, cursor: {1, 1}, token: nil}, :root)
  end

  defp parse_value(state, context \\ :other) do
    case parse_comments(state) do
      {:error, reason} ->
        {:error, reason}

      {comments, state} when is_list(comments) ->
        {current, state} = next(state)

        case parse_comments(state) do
          {:error, reason} ->
            {:error, reason}

          {new_comments, state} when is_list(new_comments) ->
            comments = comments ++ new_comments

            {value, state} =
              case {current, state} do
                {{{:delimiter, {:brace, :open}}, line, column}, state} ->
                  {node, state} = parse_object(state, {line, column})

                  case {node, state} do
                    {:error, reason} ->
                      {:error, reason}

                    _ ->
                      {{node, comments}, state}
                  end

                {{{:delimiter, {:bracket, :open}}, line, column}, state} ->
                  {node, state} = parse_array(state, {line, column})

                  case {node, state} do
                    {:error, reason} ->
                      {:error, reason}

                    _ ->
                      {{node, comments}, state}
                  end

                {{{:string, {subtype, value}}, line, column}, state} ->
                  {{%{
                      type: :string,
                      subtype: subtype,
                      value: value,
                      place: {line, column}
                    }, comments}, state}

                {{{:number, {subtype, value}}, line, column}, state} ->
                  {{%{
                      type: :number,
                      subtype: subtype,
                      value: value,
                      place: {line, column}
                    }, comments}, state}

                {{{:boolean, value}, line, column}, state} ->
                  {{%{type: :boolean, value: value, place: {line, column}}, comments}, state}

                {{nil, line, column}, state} ->
                  {{%{type: nil, place: {line, column}}, comments}, state}

                {:error, reason} ->
                  {:error, reason}

                {{token, line, column}, _} ->
                  {:error,
                   "unexpected token `#{token |> inspect()}` at line #{line} column #{column}"}

                {:done, _} ->
                  {:error, "unexpected end of input"}
              end

            case value do
              :error ->
                {:error, state}

              {value, _} = node ->
                case context do
                  :root ->
                    case peek(state) do
                      :done ->
                        {:ok, %{type: :root, value: value, comments: comments}}

                      {token, line, column} ->
                        {:error,
                         "unexpected token `#{token |> inspect()}` at line #{line} column #{column}"}
                    end

                  _ ->
                    {node, state}
                end
            end
        end
    end
  end

  defp parse_object(state, start, map \\ %{}, comments \\ [])
       when is_map(map) and is_list(comments) do
    case peek(state) do
      {{:delimiter, {:brace, :close}}, _, _} ->
        {_, state} = next(state)

        case parse_comments(state) do
          {new_comments, state} when is_list(new_comments) ->
            comments = comments ++ new_comments
            {%{type: :object, value: map, place: start, comments: comments}, state}

          {:error, reason} ->
            {:error, reason}
        end

      {{:delimiter, :comma} = token, line, column} when map == %{} ->
        {:error, "unexpected token `#{token |> inspect()}` at line #{line} column #{column}"}

      {{:delimiter, :comma}, _, _} ->
        {_, state} = next(state)

        case parse_comments(state) do
          {new_comments, state} when is_list(new_comments) ->
            comments = comments ++ new_comments
            parse_object(state, start, map, comments)

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {current, state} = next(state)

        case parse_comments(state) do
          {new_comments, state} when is_list(new_comments) ->
            comments = comments ++ new_comments

            case current do
              {{:string, {subtype, key}}, _, _} when subtype in [:single, :free] ->
                case peek(state) do
                  {{:delimiter, :colon}, _, _} ->
                    {_, state} = next(state)

                    case parse_comments(state) do
                      {new_comments, state} when is_list(new_comments) ->
                        comments = comments ++ new_comments

                        case parse_value(state) do
                          {:error, reason} ->
                            {:error, reason}

                          {{current, value_comments}, state} ->
                            map = map |> Map.put(key, current)
                            parse_object(state, start, map, comments ++ value_comments)
                        end

                      {:error, reason} ->
                        {:error, reason}
                    end

                  {token, line, column} ->
                    {:error,
                     "unexpected token `#{token |> inspect()}` at line #{line} column #{column}"}
                end

              {token, line, column} ->
                {:error,
                 "unexpected token `#{token |> inspect()}` at line #{line} column #{column}"}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp parse_array(state, start, list \\ [], comments \\ [])
       when is_list(list) and is_list(comments) do
    case peek(state) do
      {{:delimiter, {:bracket, :close}}, _, _} ->
        {_, state} = next(state)

        case parse_comments(state) do
          {:error, reason} ->
            {:error, reason}

          {new_comments, state} when is_list(new_comments) ->
            {%{type: :array, value: list, place: start, comments: comments ++ new_comments},
             state}
        end

      {{:delimiter, :comma} = token, line, column} when list == [] ->
        {:error, "unexpected token `#{token |> inspect()}` at line #{line} column #{column}"}

      {{:delimiter, :comma}, _, _} ->
        {_, state} = next(state)

        case parse_comments(state) do
          {:error, reason} ->
            {:error, reason}

          {new_comments, state} when is_list(new_comments) ->
            comments = comments ++ new_comments
            parse_array(state, start, list, comments)
        end

      _ ->
        case parse_value(state) do
          {:error, reason} ->
            {:error, reason}

          {{current, value_comments}, state} ->
            list = list ++ [current]
            parse_array(state, start, list, comments ++ value_comments)
        end
    end
  end

  defp parse_comments(state, comments \\ []) when is_list(comments) do
    case peek(state) do
      {{:comment, {subtype, value}}, line, column} ->
        {_, state} = next(state)

        parse_comments(
          state,
          comments ++ [%{type: :comment, subtype: subtype, value: value, place: {line, column}}]
        )

      {:error, reason} ->
        {:error, reason}

      _ ->
        {comments, state}
    end
  end
end
