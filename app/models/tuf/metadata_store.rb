module Tuf
  # Implentation of storage for TUF metadata files.
  #
  # TODO: Should probably be renamed to Repository.
  class MetadataStore
    def initialize(opts = {})
      @bucket = opts.fetch(:bucket)

      # TODO: This is a little backwards, need to look up the actual key to use
      # from Root and sign with that. Probably no need to inject this.
      @signer = opts.fetch(:signer, Tuf::Signer)
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
    # TODO: This is now a weird name, since this "Repository" always operates
    # on the latest snapshot.
    def latest_snapshot
      @latest_snapshot ||= begin
        timestamp = bucket.get("metadata/timestamp.txt")
        targets = if timestamp
          signed_timestamp = JSON.parse(timestamp)
          timestamp = root.unwrap_role('timestamp', signed_timestamp)

          # TODO: Verify SHA in timestamp for release matches this file,
          # otherwise vulnerable to freeze attack.
          signed_release = JSON.parse(get_hashed_metadata("metadata/release.txt", timestamp['meta']).body)
          release = root.unwrap_role('release', signed_release)

          # TODO: Verify SHA in timestamp for release matches this file,
          # otherwise vulnerable to freeze attack.
          signed_targets = JSON.parse(get_hashed_metadata("metadata/targets.txt", release['meta']).body)
          targets = root.unwrap_role('targets', signed_targets)

          targets = Targets.new(targets)
          # TODO: unclaimed should not be special, lazily fetch targets
  #         targets['delegations']['roles'].each do |delegated_role|
  #         end
          signed_unclaimed = JSON.parse(get_hashed_metadata("metadata/targets/unclaimed.txt", release['meta']).body)
          unclaimed = targets.unwrap_role('unclaimed', signed_unclaimed)

          Tuf::Metadata.new(
            unclaimed: unclaimed,
            release:   release
          )
        else
          raise "Needs bootstrap"
        end
      end
    end

    def get_hashed_target(path)
      file = Tuf::File.from_metadata(path, latest_snapshot.unclaimed['targets'][path])
      file.attach_body! bucket.get(file.path_with_hash)
    end

    def get_target(path)
      file = Tuf::File.from_metadata(path, latest_snapshot.unclaimed['targets'][path])
      file.attach_body! bucket.get(file.path)
    end

    # Publishes new root, targets, and claimed roles that have been signed by
    # an offline key. This should only be used in bootstrapping a system or
    # disaster recovery.
    def publish_offline(metadata)
      root    = build_role 'root',    metadata.root.to_hash, metadata.root
      targets = build_role 'targets', metadata.targets.to_hash, metadata.root

      metadata.replace_release(root)
      metadata.replace_release(targets)

      [root, targets].each do |file|
        bucket.create(file.path_with_hash, file.body)
      end

      publish(metadata)
    end

    # Publishes a new consistent snapshot. The only file that is overwritten is
    # the timestamp, since that is the "root" of the metadata and needs to be
    # able to be fetched independent of others. All other files are persisted
    # with their hash added to their filename.
    def publish(metadata)
      # Unclaimed has changed because we just added a new gem to it
      unclaimed = build_role 'unclaimed', metadata.unclaimed, metadata.targets

      metadata.replace_release(unclaimed)

      # Releases has changed because it refers to the latest version of uncalimed
      release = build_role 'release', metadata.release

      metadata.snapshot!(release)

      # Timestamp has changed to refer to the latest release
      timestamp = build_role 'timestamp', metadata.timestamp

      [release, unclaimed].each do |file|
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

      data = bucket.get(filespec.path_with_hash)

      filespec.attach_body!(data)
    end

    def build_role(role, content, owner = root)
      Tuf::File.new 'metadata/' + owner.path_for(role) + '.txt',
        Tuf::Serialize.canonical(owner.sign_role(role, signer, content))
    end
  end
end
