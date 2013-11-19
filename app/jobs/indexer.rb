class Indexer
  def perform
    log "Updating the index"
    update_index
    log "Finished updating the index"
  end

  def write_gem(body, spec)
    gem_file = directory.files.create(
      :body   => body.string,
      :key    => "gems/#{spec.original_name}.gem",
      :public => true
    )

    self.class.indexer.abbreviate spec
    self.class.indexer.sanitize spec

    gem_spec = directory.files.create(
      :body   => Gem.deflate(Marshal.dump(spec)),
      :key    => "quick/Marshal.4.8/#{spec.original_name}.gemspec.rz",
      :public => true
    )
  end

  def directory
    fog.directories.get($rubygems_config[:s3_bucket]) || fog.directories.create(:key => $rubygems_config[:s3_bucket])
  end

  private

  def fog
    $fog || Fog::Storage.new(
      :provider => 'Local',
      :local_root => Pusher.server_path
    )
  end

  def stringify(value)
    final = StringIO.new
    gzip = Zlib::GzipWriter.new(final)
    gzip.write(Marshal.dump(value))
    gzip.close

    final.string
  end

  def upload(key, value)
    data = stringify(value)
    hash = Digest::SHA2.hexdigest(data)

    directory.files.create(
      :body   => data,
      :key    => key,
      :public => true
    )

    ext = File.extname(key)
    key_with_hash = File.basename(key, ext) + '.' + hash + ext

    directory.files.create(
      :body   => data,
      :key    => key_with_hash,
      :public => true
    )
    [key, hash, data.length]
  end

  def update_index
    index_files = []
    index_files << upload("specs.4.8.gz", specs_index)
    log "Uploaded all specs index"
    index_files << upload("latest_specs.4.8.gz", latest_index)
    log "Uploaded latest specs index"
    index_files << upload("prerelease_specs.4.8.gz", prerelease_index)
    log "Uploaded prerelease specs index"

    # TODO: Need to keep state between runs, can't regenerate this every time.
    existing_files = Dir.chdir("server/target") do
      Dir['{gems/**/*,quick/**/*}'].map do |file|
        next if File.directory?(file)

        [file, Digest::SHA2.file(file).hexdigest, File.size(file)]
      end
    end
    Tuf.generate_metadata(index_files + existing_files)
  end

  def minimize_specs(data)
    names     = Hash.new { |h,k| h[k] = k }
    versions  = Hash.new { |h,k| h[k] = Gem::Version.new(k) }
    platforms = Hash.new { |h,k| h[k] = k }

    data.each do |row|
      row[0] = names[row[0]]
      row[1] = versions[row[1].strip]
      row[2] = platforms[row[2]]
    end

    data
  end

  def specs_index
    minimize_specs Version.rows_for_index
  end

  def latest_index
    minimize_specs Version.rows_for_latest_index
  end

  def prerelease_index
    minimize_specs Version.rows_for_prerelease_index
  end

  def log(message)
    Rails.logger.info "[GEMCUTTER:#{Time.now}] #{message}"
  end

  def self.indexer
    @indexer ||=
      begin
        indexer = Gem::Indexer.new(Pusher.server_path, :build_legacy => false)
        def indexer.say(message) end
        indexer
      end
  end
end
