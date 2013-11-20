module Tuf
  # Implentation of storage for TUF metadata files.
  class MetadataStore
    def initialize(opts = {})
      @bucket = opts.fetch(:bucket)

      # TODO: This is a little backwards, need to look up the actual key to use
      # from Root and sign with that. Probably no need to inject this.
      @signer = opts.fetch(:signer)
      @root   = Root.new(opts.fetch(:root)) # TODO: Use Gem::TUF::Root
    end

    # Returns the latest snapshot so that it can be built upon to create a new
    # snapshot. If no snapshot is present, start with a blank metadata.
    #
    # Note that this fetches metadata files from S3 everytime. There are likely
    # consistency (getting an old timestamp) or performance (it's just slow)
    # issues to this approach.
    #
    # TODO: Address the consistency concern above.
    def latest_snapshot
      timestamp = bucket.get("metadata/timestamp.txt")
      targets = if timestamp
        # TODO: root.txt
        # TODO: validate signatures

        signed_timestamp = JSON.parse(timestamp.body)

        # TODO: This probably needs to get the threshold from root and use
        # that. root.unwrap_role maybe?
        timestamp = signer.unwrap(signed_timestamp, root)

        signed_release = JSON.parse(get_hashed_metadata("metadata/release.txt", timestamp['meta']).body)

        release = signer.unwrap(signed_release, root)

        signed_targets = JSON.parse(get_hashed_metadata("metadata/targets.txt", release['meta']).body)
        signer.unwrap(signed_targets, root)
      else
        {}
      end

      Tuf::Metadata.new(targets)
    end

    # Publishes a new consistent snapshot. The only file that is overwritten is
    # the timestamp, since that is the "root" of the metadata and needs to be
    # able to be fetched independent of others. All other files are persisted
    # with their hash added to their filename.
    def publish(metadata)
      targets   = build_role 'targets',   metadata.targets
      releases  = build_role 'release',  metadata.releases([targets])
      timestamp = build_role 'timestamp', metadata.timestamp([releases])

      [targets, releases].each do |file|
        bucket.create(file.path_with_hash, file.body)
      end

      # Timestamp file does not have a hash in its path, since this is the
      # first file a client requests and as such there is no way for them to
      # know what the hash would be.
      bucket.create(timestamp.path, timestamp.body)
    end

    private

    attr_reader :bucket, :signer, :root

    def get_hashed_metadata(path, metadata)
      filespec = ::Tuf::File.from_metadata(path, metadata[path])

      data = bucket.get(filespec.path_with_hash).body

      filespec.attach_body!(data)
    end

    def build_role(role, content)
      Tuf::File.new 'metadata/' + role + '.txt',
        Tuf::Serialize.canonical(root.sign_role(role, signer, content))
    end
  end
end
