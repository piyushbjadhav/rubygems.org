class Indexer
  def perform
    log "Updating the index"
    update_index
    log "Finished updating the index"
  end

  def write_gem(body, spec)
    gem_file = Tuf::File.from_body(
      "gems/#{spec.original_name}.gem",
      body.string
    )

    self.class.indexer.abbreviate spec
    self.class.indexer.sanitize spec

    gem_spec = Tuf::File.from_body(
      "quick/Marshal.4.8/#{spec.original_name}.gemspec.rz",
      Gem.deflate(Marshal.dump(spec))
    )

    files = [
      gem_file,
      gem_spec,
    ]

    files.each do |file|
      directory.files.create(
        :key    => file.path,
        :body   => file.body,
        :public => true
      )
    end

    tuf_pending_store.add(files)
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
    file = Tuf::File.from_body(key, data)

    directory.files.create(
      :key    => file.path,
      :body   => file.body,
      :public => true
    )

    # TODO: Document why we do this.
    directory.files.create(
      :key    => file.path_with_hash,
      :body   => file.body,
      :public => true
    )

    file
  end

  def tuf_pending_store
    @tuf_pending_store ||= Tuf::RedisPendingStore.new($redis)
  end

  def tuf_store
    @tuf_store ||= Tuf::S3Store.new(
      bucket: directory,
      # TODO: Replace with Rubygems::Tuf::Signer
      signer: Tuf::InsecureSigner.new(*online_key),
    )
  end

  def online_key
    # TODO: Use a real key
    ['online123', {
      'keytype' => 'stupid',
      'keyval' => {
        'private' => '',
        'public'  => 'insecure123',
      }
    }]
  end

  def update_index
    index_files = []
    index_files << upload("specs.4.8.gz", specs_index)
    log "Uploaded all specs index"
    index_files << upload("latest_specs.4.8.gz", latest_index)
    log "Uploaded latest specs index"
    index_files << upload("prerelease_specs.4.8.gz", prerelease_index)
    log "Uploaded prerelease specs index"

    metadata = tuf_store.latest_snapshot
    metadata.replace_targets(index_files)
    pending_files = tuf_pending_store.pending
    pending_files.each do |file|
      metadata.add_target(file)
    end
    tuf_store.publish(metadata)
    tuf_pending_store.clear(pending_files)
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
