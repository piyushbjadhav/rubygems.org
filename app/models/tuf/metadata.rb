module Tuf
  # Responsible for create and update of "signed" sections inside TUF metadata
  # files.
  class Metadata
    attr_reader :existing

    def initialize(existing)
      @existing = existing
    end

    def root
      existing.fetch(:root)
    end

    # For replacing mutable files in targets. Will add if path does not
    # already exist.
#     def replace_targets(targets)
#       targets.each do |file|
#         @target_files[file.path] = file.to_hash
#       end
#     end

    def replace_release(file)
      releases['meta'][file.path] = file.to_hash
    end

    # For adding immutable files to targets. Will raise if path already exists.
    def add_target(file)
      if @target_files[file.path]
        raise "#{file.path} already exists, not replacing"
      end

      @target_files[file.path] = file.to_hash
    end

    # TODO: How to handle delegated targets?
    def targets
      unclaimed_key = Tuf::Key.new(
        'keytype' => "insecure",
        'keyval' => {
          'private' => "",
          'public' => "insecure-unclamied",
        }
      )
      @targets ||= Targets.new(JSON.parse({
        _type:   "Targets",
        expires: clock.now + 1000, # TODO
        targets: {},
        version: 2,
        delegations: {
          keys: {
            unclaimed_key.id => unclaimed_key.to_hash
          }, # TODO
          roles: [{
            name: 'unclaimed',
            keyids: [unclaimed_key.id],
            threshold: 1,
          }]
        }
      }.to_json))
    end

    def unclaimed
      {
        _type:   "Targets",
        expires: clock.now + 1000, # TODO
        targets: target_files,
        version: 2,
      }
    end

    def snapshot!(releases)
      @timestamp = {
        _type: "Timestamp",
        expires: clock.now + 1000, # TODO
        meta: {
          releases.path => releases.to_hash
        },
        version: 2,
      }
    end

    def releases
      # TODO: Stringify all of this
      @releases ||= {
        _type:   "Releases",
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
