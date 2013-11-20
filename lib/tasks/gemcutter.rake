namespace :gemcutter do
  namespace :tuf do
    task generate_metadata: :environment do
      Indexer.new.perform
    end

    task generate_fake_root: :environment do
      offline_key = Tuf::Key.new(
        'keytype' => "insecure",
        'keyval' => {
          'private' => "",
          'public' => "insecure-offline",
        }
      )

      online_key = Tuf::Key.new(
        'keytype' => "insecure",
        'keyval' => {
          'private' => "",
          'public' => "insecure-online",
        }
      )

      root = {
        _type:   "Root",
        ts:      Time.now.utc,
        expires: Time.now.utc + 10000, # TODO: There is a recommend value in pec
        keys: {
          online_key.id  => online_key.to_hash,
          offline_key.id => offline_key.to_hash
        },
        roles: {
          # TODO: Once delegated targets are operational, the root
          # targets.txt should use an offline key.
          root:      {keyids: [offline_key.id], threshold: 1},
          timestamp: {keyids: [online_key.id], threshold: 1},
          release:   {keyids: [online_key.id], threshold: 1},
          targets:   {keyids: [online_key.id], threshold: 1},
        }
      }

      root = JSON.parse(root.to_json) # Stringify keys

      path     = "config/root.txt"
      signer   = Tuf::Signer
      document = signer.sign(signer.wrap(root), offline_key)
      File.write(path, Tuf::Serialize.canonical(document))
      File.chmod(0600, path)
    end
  end

  namespace :index do
    desc "Update the index"
    task :update => :environment do
      require 'benchmark'
      Benchmark.bm do|b|
        b.report("update index") { Indexer.new.perform }
      end
    end
  end

  namespace :import do
    desc 'Bring the gems through the gemcutter process'
    task :process => :environment do
      gems = Dir[File.join(ARGV[1] || "#{Gem.path.first}/cache", "*.gem")].sort.reverse
      puts "Processing #{gems.size} gems..."
      gems.each do |path|
        puts "Processing #{path}"
        cutter = Pusher.new(nil, File.open(path))

        cutter.process
      end
    end
  end

  namespace :rubygems do
    desc "update rubygems. run as: rake gemcutter:rubygems:update VERSION=[version number] RAILS_ENV=[staging|production] S3_KEY=[key] S3_SECRET=[secret]"
    task :update => :environment do
      version     = ENV["VERSION"]
      app_path    = Rails.root.join("config", "application.rb")
      old_content = app_path.read
      new_content = old_content.gsub(/RUBYGEMS_VERSION = "(.*)"/, %{RUBYGEMS_VERSION = "#{version}"})

      app_path.open("w") do |file|
        file.write new_content
      end

      updater = Indexer.new
      html    = Nokogiri.parse(open("http://rubyforge.org/frs/?group_id=126"))
      links   = html.css("a[href*='#{version}']").map { |n| n["href"] }

      if links.empty?
        abort "gem/tgz/zip for RubyGems #{version} hasn't been uploaded yet!"
      else
        links.each do |link|
          url = "http://rubyforge.org#{link}"

          puts "Uploading #{url}..."
          updater.directory.files.create({
            :body   => open(url).read,
            :key    => "rubygems/#{File.basename(url)}",
            :public => true
          })
        end
      end
    end

    desc "Update the download counts for all gems."
    task :update_download_counts => :environment do
      case_query = Rubygem.pluck(:name)
        .map { |name| "WHEN '#{name}' THEN #{$redis["downloads:rubygem:#{name}"].to_i}" }
        .join("\n            ")

      ActiveRecord::Base.connection.execute <<-SQL.strip_heredoc
        UPDATE rubygems
          SET downloads = CASE name
            #{case_query}
          END
      SQL
    end
  end

  desc "Move all but the last 2 days of version history to SQL"
  task :migrate_history => :environment do
    Download.copy_all_to_sql do |t,c,v|
      puts "#{c} of #{t}: #{v.full_name}"
    end
  end
end
