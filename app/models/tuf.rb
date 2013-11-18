require 'json'
require 'fileutils'

class Tuf
  def self.generate_metadata!
    FileUtils.mkdir_p("server/metadata") # TODO: Abstract this

    targets = {
      signatures: [],
      version: 2,
      signed: {
        _type: "Targets",
        expires: Time.now + 10000, # TODO: There is a recommend value in pec
        targets: {},
      },
    }

    Dir.chdir("server") do
      Dir['target/**/*'].each do |file|
        unless File.directory?(file)
          hash = Digest::SHA2.file(file).hexdigest
          targets[:signed][:targets][file] = {
            hashes: {
              sha256: hash
            },
            length: File.size(file)
          }
        end
      end
    end

    # TODO: Actually sign with something
    targets_sig = Digest::MD5.hexdigest(targets[:signed].to_json)

    targets[:signatures] = [{
      keyid:  'md5lol',
      method: 'md5lol',
      sig:    targets_sig,
    }]
    require 'pp'
    pp targets

    # TODO: where should this live?
    File.write('server/metadata/targets.txt', targets.to_json)

    # create root.txt
    roles = [:release, :root, :targets, :timestamp]

    root = {
      signed: {
        _type: "Root",
        expires: Time.now + 10000, # TODO: There is a recommend value in pec
        keys: {
          abc123: {
            keytype: "md5lol",
            keyval: {
              private: "",
              public: "asdfasdfsadfsadlkfjsad",
            }
          }
        },
        roles: roles.each_with_object({}) do |role, hash|
          hash[role] = {
            keyids: ["abc123"],
            threshold: 1,
          }
        end
      }
    }

    root_sig = Digest::MD5.hexdigest(root[:signed].to_json)

    root[:signatures] = [{
      keyid:  'md5lol',
      method: 'md5lol',
      sig:    root_sig,
    }]
    File.write('server/metadata/root.txt', root.to_json)

    pp root


    release = {
      signatures: [],
      version: 2,
      signed: {
        _type: "Release",
        expires: Time.now + 10000, # TODO: There is a recommend value in pec
        meta: {},
      },
    }

    Dir.chdir("server/metadata") do
      %w(root.txt targets.txt).each do |file|
        hash = Digest::SHA2.file(file).hexdigest
        release[:signed][:meta][file] = {
          hashes: {
            sha256: hash
          },
          length: File.size(file)
        }
      end
    end

    # TODO: Actually sign with something
    release_sig = Digest::MD5.hexdigest(release[:signed].to_json)

    release[:signatures] = [{
      keyid:  'md5lol',
      method: 'md5lol',
      sig:    release_sig,
    }]

    File.write('server/metadata/release.txt', release.to_json)
    require 'pp'
    pp release

    timestamp = {
      signatures: [],
      version: 2,
      signed: {
        _type: "Timestamp",
        expires: Time.now + 10000, # TODO: There is a recommend value in pec
        meta: {},
      },
    }

    Dir.chdir("server/metadata") do
      %w(release.txt).each do |file|
        hash = Digest::SHA2.file(file).hexdigest
        timestamp[:signed][:meta][file] = {
          hashes: {
            sha256: hash
          },
          length: File.size(file)
        }
      end
    end

    timestamp_sig = Digest::MD5.hexdigest(timestamp[:signed].to_json)

    timestamp[:signatures] = [{
      keyid:  'md5lol',
      method: 'md5lol',
      sig:    timestamp_sig,
    }]
    File.write('server/metadata/timestamp.txt', timestamp.to_json)
    pp timestamp
  end
end
