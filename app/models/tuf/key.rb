module Tuf
  # Value object for working with TUF key hashes.
  class Key
    def initialize(key)
      @key     = key
      @id      = Digest::SHA256.hexdigest(Tuf::Serialize.canonical(key))
      @public  = key.fetch('keyval').fetch('public')
      @private = key.fetch('keyval').fetch('private')
      @type    = key.fetch('keytype')
    end

    def sign(content)
      case type
      when 'insecure'
        Digest::MD5.hexdigest(public + content)
      else raise "Unknown key type: #{type}"
      end
    end

    def valid_digest?(content, expected_digest)
      # TODO: need secure equals here?
      expected_digest == Digest::MD5.hexdigest(public + content)
    end

    def to_hash
      {
        'keytype' => type,
        'keyval' => {
          'private' => private,
          'public' => public,
        }
      }
    end

    attr_reader :id, :public, :private, :type
  end
end
