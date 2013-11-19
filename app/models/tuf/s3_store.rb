module Tuf
  # Implentation of storage for TUF metadata files on S3.
  #
  # TODO: There is a lot of non-S3 logic in here, suggestion another division
  # of responsibility. Putting an interface infront of bucket.files.create
  # would be useful elsewhere (such as the Indexer).
  class S3Store
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
      timestamp = bucket.files.get("metadata/timestamp.txt")
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
      targets = Tuf::File.new(
        'metadata/targets.txt',
        canonical_json(signer.sign(metadata.targets))
      )

      releases = Tuf::File.new(
        'metadata/releases.txt',
        canonical_json(signer.sign(metadata.releases([targets]))) # TODO: Include root.txt
      )

      timestamp = Tuf::File.new(
        'metadata/timestamp.txt',
        canonical_json(signer.sign(metadata.timestamp([releases])))
      )

      [targets, releases].each do |file|
        bucket.files.create(
          key:    file.path_with_hash,
          body:   file.body,
          public: true,
        )
      end

      bucket.files.create(
        key:    timestamp.path,
        body:   timestamp.body,
        public: true,
      )
    end

    private

    attr_reader :bucket, :signer

    def canonical_json(object)
      JSON.pretty_generate(object) # TODO: Actually use canonical JSON
    end

    def get_hashed_metadata(path, metadata)
      filespec = ::Tuf::File.from_metadata(path, metadata[path])

      data = bucket.files.get(filespec.path_with_hash).body

      filespec.attach_body!(data)
    end
  end
end
