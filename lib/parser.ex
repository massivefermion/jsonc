defmodule JSONC.Parser do
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
    case start_tokenizer(content) do
      {:error, reason} ->
        {:error, reason}

      _ ->
        case parse_value(:root) do
          {:ok, result} ->
            stop_tokenizer()
            {:ok, result}

          {:error, reason} ->
            stop_tokenizer()
            {:error, reason}
        end
    end
  end

  defp parse_value(context \\ :other) do
    case parse_comments() do
      comments when is_list(comments) ->
        current = next()

        case parse_comments() do
          new_comments when is_list(new_comments) ->
            comments = comments ++ new_comments

            value =
              case current do
                {{:delimiter, {:brace, :open}}, line, column} ->
                  node = parse_object({line, column})

                  case node do
                    {:error, reason} ->
                      {:error, reason}

                    _ ->
                      {node, []}
                  end

                {{:delimiter, {:bracket, :open}}, line, column} ->
                  node = parse_array({line, column})

                  case node do
                    {:error, reason} ->
                      {:error, reason}

                    _ ->
                      {node, []}
                  end

                {{:string, {subtype, value}}, line, column} ->
                  {%{
                     type: :string,
                     subtype: subtype,
                     value: value,
                     place: {line, column}
                   }, comments}

                {{:number, {subtype, value}}, line, column} ->
                  {%{
                     type: :number,
                     subtype: subtype,
                     value: value,
                     place: {line, column}
                   }, comments}

                {{:boolean, value}, line, column} ->
                  {%{type: :boolean, value: value, place: {line, column}}, comments}

                {nil, line, column} ->
                  {%{type: nil, place: {line, column}}, comments}

                {:error, reason} ->
                  {:error, reason}

                {_ = token, line, column} ->
                  {:error,
                   "unexpected token `#{token |> inspect()}` at line #{line} column #{column}#1"}
              end

            case parse_comments() do
              new_comments when is_list(new_comments) ->
                comments = comments ++ new_comments

                case value do
                  {:error, reason} ->
                    {:error, reason}

                  {value, _} = node ->
                    peeked = peek()

                    case context do
                      :root ->
                        case peeked do
                          :done ->
                            {:ok, %{type: :root, value: value, comments: comments}}

                          {_ = token, line, column} ->
                            {:error,
                             "unexpected token `#{token |> inspect()}` at line #{line} column #{column}#2"}
                        end

                      _ ->
                        node
                    end
                end

              {:error, reason} ->
                {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_object(start, map \\ %{}, comments \\ [])
       when is_map(map) and is_list(comments) do
    peeked = peek()

    case peeked do
      {{:delimiter, {:brace, :close}}, _, _} ->
        case parse_comments() do
          new_comments when is_list(new_comments) ->
            comments = comments ++ new_comments
            next()

            case parse_comments() do
              new_comments when is_list(new_comments) ->
                comments = comments ++ new_comments
                %{type: :object, value: map, place: start, comments: comments}

              {:error, reason} ->
                {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {{:delimiter, :comma} = token, line, column} when map == %{} ->
        {:error, "unexpected token `#{token |> inspect()}` at line #{line} column #{column}#3"}

      {{:delimiter, :comma}, _, _} ->
        case parse_comments() do
          new_comments when is_list(new_comments) ->
            comments = comments ++ new_comments
            next()

            case parse_comments() do
              new_comments when is_list(new_comments) ->
                comments = comments ++ new_comments
                parse_object(start, map, comments)

              {:error, reason} ->
                {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        hopefully_key = next()

        case parse_comments() do
          new_comments when is_list(new_comments) ->
            comments = comments ++ new_comments

            case hopefully_key do
              {{:key, key}, _, _} ->
                hopefully_colon = next()

                case parse_comments() do
                  new_comments when is_list(new_comments) ->
                    comments = comments ++ new_comments

                    case hopefully_colon do
                      {{:delimiter, :colon}, _, _} ->
                        case parse_value() do
                          {:error, reason} ->
                            {:error, reason}

                          {current, value_comments} ->
                            map = map |> Map.put(key, current)
                            parse_object(start, map, comments ++ value_comments)
                        end

                      {token, line, column} ->
                        {:error,
                         "unexpected token `#{token |> inspect()}` at line #{line} column #{column}#4"}
                    end

                  {:error, reason} ->
                    {:error, reason}
                end

              {{:string, {subtype, key}}, _, _} when subtype in [:single, :free] ->
                peeked = peek()

                case peeked do
                  {{:delimiter, :colon}, _, _} ->
                    next()

                    case parse_comments() do
                      new_comments when is_list(new_comments) ->
                        comments = comments ++ new_comments

                        case parse_value() do
                          {:error, reason} ->
                            {:error, reason}

                          {current, value_comments} ->
                            map = map |> Map.put(key, current)
                            parse_object(start, map, comments ++ value_comments)
                        end

                      {:error, reason} ->
                        {:error, reason}
                    end

                  {token, line, column} ->
                    {:error,
                     "unexpected token `#{token |> inspect()}` at line #{line} column #{column}#5"}
                end

              {token, line, column} ->
                {:error,
                 "unexpected token `#{token |> inspect()}` at line #{line} column #{column}#6"}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp parse_array(start, list \\ [], comments \\ [])
       when is_list(list) and is_list(comments) do
    peeked = peek()

    case peeked do
      {{:delimiter, {:bracket, :close}}, _, _} ->
        case parse_comments() do
          new_comments when is_list(new_comments) ->
            comments = comments ++ new_comments
            next()

            case parse_comments() do
              new_comments when is_list(new_comments) ->
                comments = comments ++ new_comments
                %{type: :array, value: list, place: start, comments: comments}

              {:error, reason} ->
                {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {{:delimiter, :comma} = token, line, column} when list == [] ->
        {:error, "unexpected token `#{token |> inspect()}` at line #{line} column #{column}#7"}

      {{:delimiter, :comma}, _, _} ->
        case parse_comments() do
          new_comments when is_list(new_comments) ->
            comments = comments ++ new_comments
            next()

            case parse_comments() do
              new_comments when is_list(new_comments) ->
                comments = comments ++ new_comments
                parse_array(start, list, comments)

              {:error, reason} ->
                {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        case parse_value() do
          {:error, reason} ->
            {:error, reason}

          {current, value_comments} ->
            list = list ++ [current]
            parse_array(start, list, comments ++ value_comments)
        end
    end
  end

  defp parse_comments(comments \\ []) when is_list(comments) do
    peeked = peek()

    case peeked do
      {{:comment, {subtype, value}}, line, column} ->
        next()

        parse_comments(
          comments ++ [%{type: :comment, subtype: subtype, value: value, place: {line, column}}]
        )

      {:error, reason} ->
        {:error, reason}

      _ ->
        comments
    end
  end
end
