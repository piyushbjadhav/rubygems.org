require 'json'

module Tuf
  class Signer
    class << self
      def sign(wrapped_document, key)
        to_sign = Tuf::Serialize.canonical(wrapped_document.fetch('signed'))

        signed = wrapped_document.dup
        signed['signatures'] << {
          keyid:  key.id,
          method: key.type,
          sig:    key.sign(to_sign)
        }
        signed
      end

      def wrap(to_sign)
        {
          'signatures' => [],
          'signed'     => to_sign,
        }
      end

      def unwrap(signed_document, keystore)
        verify!(signed_document, keystore)
        unwrap_unsafe(signed_document)
      end

      # Unwrap a document without verifying signatures. This should only ever
      # be used internal to this class, or in a bootstrapping situation (such
      # as root.txt) where you are going to verify the document later.
      #
      # All external uses of this method MUST have explicit documentation
      # justifying that use.
      def unwrap_unsafe(signed_document)
        signed_document.fetch('signed')
      end

      private

      def verify!(signed_document, keystore)
        document = Tuf::Serialize.canonical(unwrap_unsafe(signed_document))

        signed_document.fetch('signatures').each do |sig|
          key_id = sig.fetch('keyid')
          method = sig.fetch('method')

          key = keystore.fetch(key_id)
          key.valid_digest?(document, sig.fetch('sig')) ||
            raise("Invalid signature for #{key_id}")
        end
      end
    end
  end
end
