require 'json'

module Tuf
  # For testing only, don't actually use this.
  class InsecureSigner
    def initialize(key_id, key)
      @key_id = key_id
      @key    = key
    end

    def sign(hash)
      salt   = key['keyval']['public']
      signed = canonical_json(hash)

      {
        signatures: {
          keyid:  key_id,
          method: 'insecure',
          sig:    Digest::MD5.hexdigest(salt + signed),
        },
        signed: hash,
      }
    end

    private

    attr_reader :key, :key_id

    def canonical_json(object)
      JSON.pretty_generate(object) # TODO: Actually use canonical JSON
    end
  end
end
