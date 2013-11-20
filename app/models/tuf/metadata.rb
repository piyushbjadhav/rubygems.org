module Tuf
  # Responsible for create and update of "signed" sections inside TUF metadata
  # files.
  class Metadata
    def initialize(targets)
      @target_files = targets.fetch('targets', {})
    end

    # For replacing mutable files in targets. Will add if path does not
    # already exist.
    def replace_targets(targets)
      targets.each do |file|
        @target_files[file.path] = file.to_hash
      end
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
      {
        _type:   "Targets",
        expires: clock.now + 1000, # TODO
        targets: target_files,
        version: 2,
      }
    end

    def releases(files)
      {
        _type: "Releases",
        expires: clock.now + 1000, # TODO
        meta: files.each_with_object({}) {|file, hash|
          hash[file.path] = file.to_hash
        },
        version: 2,
      }
    end

    def timestamp(files)
      {
        _type: "Timestamp",
        expires: clock.now + 1000, # TODO
        meta: files.each_with_object({}) {|file, hash|
          hash[file.path] = file.to_hash
        },
        version: 2,
      }
    end

    def clock
      Time # TODO: DI
    end

    private

    attr_reader :target_files
  end
end
