module Tuf
  # Responsible for create and update of "signed" sections inside TUF metadata
  # files.
  class Metadata
    attr_reader :existing

    def initialize(existing)
      @existing = existing
      @unclaimed = existing[:unclaimed]
      @release   = existing[:release]
    end

    def root
      existing.fetch(:root)
    end

    # For replacing mutable files in targets. Will add if path does not
    # already exist.
    def replace_unclaimed(targets)
      targets.each do |file|
        @unclaimed['targets'][file.path] = file.to_hash
      end
    end

    def replace_release(file)
      release['meta'][file.path] = file.to_hash
    end

    # For adding immutable files to targets. Will raise if path already exists.
    # TODO: Consistent interface with replace_unclaimed
    def add_unclaimed(file)
      if @unclaimed['targets'][file.path]
        raise "#{file.path} already exists, not replacing"
      end

      @unclaimed['targets'][file.path] = file.to_hash
    end

    # TODO: How to handle delegated targets?
    def targets
      online_key = Tuf::Key.new(
        'keytype' => "insecure",
        'keyval' => {
          'private' => "",
          'public' => "insecure-unclamied",
        }
      )
      offline_key = Tuf::Key.new(
        'keytype' => "insecure",
        'keyval' => {
          'private' => "",
          'public' => "insecure-clamied",
        }
      )
      @targets ||= Targets.new(JSON.parse({
        _type:   "Targets",
        expires: clock.now + 1000, # TODO
        targets: {},
        version: 2,
        delegations: {
          keys: {
            online_key.id  => online_key.to_hash,
            offline_key.id => offline_key.to_hash
          }, # TODO
          roles: [{
            name: 'claimed',
            keyids: [offline_key.id],
            threshold: 1, # TODO: More than 1
          }, {
            name: 'recently-claimed',
            keyids: [online_key.id],
            threshold: 1,
          }, {
            name: 'unclaimed',
            keyids: [online_key.id],
            threshold: 1,
          }]
        }
      }.to_json))
    end

    def unclaimed
      @unclaimed ||= JSON.parse({
        _type:   "Targets",
        expires: clock.now + 1000, # TODO
        targets: {},
        version: 2,
      }.to_json)
    end

    def recently_claimed
      @recently_claimed ||= JSON.parse({
        _type:   "Targets",
        expires: clock.now + 1000, # TODO
        targets: {},
        version: 2,
      }.to_json)
    end

    def claimed
      @claimed ||= JSON.parse({
        _type:   "Targets",
        expires: clock.now + 1000, # TODO
        targets: {},
        version: 2,
      }.to_json)
    end

    def snapshot!(release)
      @timestamp = {
        _type: "Timestamp",
        expires: clock.now + 1000, # TODO
        meta: {
          release.path => release.to_hash
        },
        version: 2,
      }
    end

    def release
      # TODO: Stringify all of this
      @release ||= {
        _type:   "Release",
        expires: clock.now + 1000, # TODO
        'meta' => {},
        version: 2,
      }
    end

    def timestamp
      @timestamp || raise("No current snapshot!")
    end

    def clock
      Time # TODO: DI
    end

    private

    attr_reader :target_files
  end
end
