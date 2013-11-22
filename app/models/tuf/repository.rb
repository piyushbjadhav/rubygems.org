require 'fileutils'

module Tuf
  class Repository
    def initialize(opts)
      @bucket = opts.fetch(:bucket)
      @root   = Root.new(opts.fetch(:root))
    end

    def target(path)
      metadata = find_metadata path, 'targets', root

      if metadata
        file = Tuf::File.from_metadata(path, metadata)
        file.attach_body! bucket.get(path, cache_key: file.path_with_hash)
      end
    end

    private

    def release
      @release ||= begin
         file = timestamp.fetch_role('release', root)

         # TODO: Check expiry
         Role::Release.new(file, @bucket)
       end
    end

    def timestamp
      @timestamp ||= begin
        signed_file = JSON.parse(bucket.get("metadata/timestamp.txt", cache: false))
        
        # TODO: Check expiry
        Role::Timestamp.new(root.unwrap_role('timestamp', signed_file), @bucket)
      end
    end

    def find_metadata(path, role, parent)
      targets = Targets.new(release.fetch_role(role, parent))

      if targets.files[path]
        targets.files[path]
      else
        targets.delegated_roles.each do |role|
          x = find_metadata(path, role.fetch('name'), targets)
          return x if x
        end
        nil
      end
    end

    attr_reader :bucket, :root

    module Role
      class Metadata
        def initialize(source, bucket)
          @role_metadata = source['meta']
          @bucket = bucket
        end

        def fetch_role(role, parent)
          path = "metadata/" + parent.path_for(role) + ".txt"

          metadata = role_metadata.fetch(path) {
            raise "Could not find #{path} in: #{role_metadata.keys.sort.join("\n")}"
          }

          filespec = ::Tuf::File.from_metadata(path, role_metadata[path])

          data = bucket.get(filespec.path_with_hash)

          signed_file = filespec.attach_body!(data)

          parent.unwrap_role(role, JSON.parse(signed_file.body))
        end

        attr_reader :role_metadata, :bucket
      end

      class Timestamp < Metadata
      end

      class Release < Metadata
      end
    end
  end
end
