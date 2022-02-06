defmodule JSONC do
  import JSONC.Parser

  def main do
    sample = File.read!("sample.jsonc")
    parse(sample)
  end
end
