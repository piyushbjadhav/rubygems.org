module Tuf
  class Serialize
    def self.canonical(document)
      # TODO: Use CanonicalJSON
      JSON.pretty_generate(document)
    end
  end
end
