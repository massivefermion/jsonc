defmodule JSONC do
  defdelegate decode!(content), to: JSONC.Decoder
  defdelegate decode(content), to: JSONC.Decoder
end
