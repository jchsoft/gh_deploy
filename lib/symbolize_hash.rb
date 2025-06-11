# frozen_string_literal: true

# Extends Hash class with symbolize_keys method
class ::Hash
  def symbolize_keys
    each_with_object({}) do |(k, v), acc|
      key = k.is_a?(String) ? k.to_sym : k
      value = v.is_a?(Hash) ? v.symbolize_keys : v
      acc[key] = value
    end
  end
end
