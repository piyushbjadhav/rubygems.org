module Tuf
  # TODO: Justify this class' existence.
  # Maybe it's actually a Keystore? Owner?
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

    def to_hash
      @root
    end

    def path_for(role)
      role
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

  # TODO: DRY this up with above
  class Targets
    def initialize(content)
      # TODO: Can't use unwrap_unsafe here, need to unwrap with root
      @target = content
      @root = @target.fetch('delegations', {})
    end

    def sign_role(role, signer, content)
      role_info = root['roles'].detect {|x| x['name'] == role }
      role_info['keyids'].inject(signer.wrap(content)) do |content, key_id|
        signer.sign(content, key(key_id))
      end
    end

    def unwrap_role(role, content)
      # TODO: get threshold for role rather than requiring all signatures to be
      # valid.
      Tuf::Signer.unwrap(content, self)
    end

    def to_hash
      @target
    end

    def files
      @target.fetch('targets')
    end

    def delegated_roles
      @root.fetch('roles', [])
    end

    def fetch(key_id)
      key(key_id)
    end

    def path_for(role)
      "targets/#{role}"
    end

    def delegations
      @root['roles']
    end

    private

    attr_reader :root

    def key(key_id)
      Tuf::Key.new(root['keys'].fetch(key_id))
    end
  end
end
