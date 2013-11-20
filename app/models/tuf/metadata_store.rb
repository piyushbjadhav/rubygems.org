module Tuf
  # Implentation of storage for TUF metadata files.
  class MetadataStore
    def initialize(opts = {})
      @bucket = opts.fetch(:bucket)
      @signer = opts.fetch(:signer)
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
      if timestamp
        # TODO: root.txt
        # TODO: validate signatures

        timestamp = JSON.parse(timestamp.body)
        releases = JSON.parse(get_hashed_metadata("metadata/releases.txt", timestamp['signed']['meta']).body)
        targets  = JSON.parse(get_hashed_metadata("metadata/targets.txt", releases['signed']['meta']).body)

        Tuf::Metadata.new(targets.fetch('signed'))
      else
        Tuf::Metadata.new
      end
    end

    # Publishes a new consistent snapshot. The only file that is overwritten is
    # the timestamp, since that is the "root" of the metadata and needs to be
    # able to be fetched independent of others. All other files are persisted
    # with their hash added to their filename.
    def publish(metadata)
      targets   = build_meta 'targets.txt',   metadata.targets
      releases  = build_meta 'releases.txt',  metadata.releases([targets])
      timestamp = build_meta 'timestamp.txt', metadata.timestamp([releases])

      [targets, releases].each do |file|
        bucket.create(file.path_with_hash, file.body)
      end

      # Timestamp file does not have a hash in its path, since this is the
      # first file a client requests and as such there is no way for them to
      # know what the hash would be.
      bucket.create(timestamp.path, timestamp.body)
    end

    private

    attr_reader :bucket, :signer

    def canonical_json(object)
      JSON.pretty_generate(object) # TODO: Actually use canonical JSON
    end

    def get_hashed_metadata(path, metadata)
      filespec = ::Tuf::File.from_metadata(path, metadata[path])

      data = bucket.get(filespec.path_with_hash).body

      filespec.attach_body!(data)
    end

    def build_file(path, content)
      Tuf::File.new 'metadata/' + path, canonical_json(signer.sign(content))
    end
  end
end
