require 'openssl'
require 'rubygems/tuf'

module Tuf

  # A grab bag of methods used to bootstrap TUF specifically for gemcutter.
  class Gemcutter
    def generate_key
      rsa = OpenSSL::PKey::RSA.new(2048, 65537)
      Gem::TUF::Key.build('rsa', rsa.to_pem, rsa.public_key.to_pem)
    end

    def generate_root(online_keys, offline_keys)
      root = Gem::TUF::Role::Root.empty
      root.add_roles(
        'root'      => offline_keys,
        'targets'   => offline_keys,
        'release'   => online_keys,
        'timestamp' => online_keys,
      )

      signer.wrap(root.to_hash)
    end

    def generate_targets(online_keys, offline_keys)
      targets = Gem::TUF::Role::Targets.empty
      targets.delegate_to('targets/claimed', offline_keys)
      targets.delegate_to('targets/recently-claimed', online_keys)
      targets.delegate_to('targets/unclaimed', online_keys)

      signer.wrap(targets.to_hash)
    end

    def generate_claimed
      signer.wrap Gem::TUF::Role::Targets.empty
    end

    def sign_file(key, path)
      signed = signer.sign(JSON.parse(File.read(path)), key)

      File.write path, Gem::TUF::Serialize.canonical(signed)
    end

    def bootstrap!(bucket, online_key, signed_files)
      repo = Tuf::OnlineRepository.new(
        bucket:     bucket,
        online_key: online_key,
        root:       signed_files.fetch('root')
      )
      repo.bootstrap!

      unclaimed = Gem::TUF::Role::Targets.empty
      recent    = Gem::TUF::Role::Targets.empty

      signed_files['targets/recently-claimed'] = signer.sign_unwrapped(unclaimed.to_hash, online_key)
      signed_files['targets/unclaimed']        = signer.sign_unwrapped(recent.to_hash, online_key)

      repo.add_signed_delegated_role('targets', 'root', signed_files.fetch('targets'))
      repo.add_signed_delegated_role('targets/claimed', 'targets', signed_files.fetch('targets/claimed'))
      repo.add_signed_delegated_role('targets/recently-claimed', 'targets', signed_files.fetch('targets/recently-claimed'))
      repo.add_signed_delegated_role('targets/unclaimed', 'targets', signed_files.fetch('targets/unclaimed'))

      repo.publish!
    end

    def signer
      Gem::TUF::Signer
    end
  end
end
