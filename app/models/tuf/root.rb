module Tuf
  # TODO: Justify this class' existence.
  class Root
    def initialize(content)
      # TODO: Justify use of unwrap_unsafe by documenting how this file is
      # verified.
      @root = Tuf::Signer.unwrap_unsafe(JSON.parse(content))
    end

    def sign_role(role, signer, content)
      role_info = root['roles'][role]
      role_info['keyids'].inject(signer.wrap(content)) do |content, key_id|
        signer.sign(content, key(key_id))
      end
    end

    def unwrap_role(role, content)
      # TODO: get threshold for role rather than requiring all signatures to be
      # valid.
      Tuf::Signer.unwrap(content, self)
    end

    def fetch(key_id)
      key(key_id)
    end

    private

    attr_reader :root

    def key(key_id)
      Tuf::Key.new(root['keys'].fetch(key_id))
    end
  end
end
