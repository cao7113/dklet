custom_commands do
  desc 'rails_boot', 'run rails boot script'
  def rails_boot
    #docker-compose exec website rails db:reset
    # todo always create test db  
    container_run <<~Desc
      rails db:create 2>/dev/null
    Desc
    invoke :db_migrate
  end

  desc 'rails_console', 'run into rails console'
  def rails_console
    container_run "rails console"
  end

  desc 'db_migrate', 'run db migrate'
  def db_migrate
    container_run <<~Desc
      rails db:migrate
    Desc
  end

  desc 'browse', 'open browser'
  def browse(tp = :web)
    domain = fetch("#{tp}_domain".to_sym)
    return unless domain
    doms = domain.split(',')
    system <<~Desc
      open http://#{doms.first}
    Desc
  end
  map 'open' => 'browse'

  desc 'config', 'show env config'
  option :backup, type: :boolean, banner: 'backup current config', aliases: ["b"]
  option :link, type: :boolean, banner: 'link config to local', aliases: ["l"]
  def config
    puts "# env config file:"
    puts "# #{local_env_file}"
    puts "#" * 40
    puts local_env_file.read

    if options[:backup]
      path = script_path.join("local/backup/#{env}")
      path.mkpath
      dest = "#{path}/env.local-#{Dklet::Util.human_timestamp}"
      system <<~Desc
        cp #{local_env_file} #{dest} 
      Desc
      puts "==back config to #{dest}"
    end

    if options[:link]
      dest = script_path.join("local/#{env}-env.local")
      dest.parent.mkpath
      system <<~Desc
        ln -sf #{local_env_file} #{dest} 
      Desc
      puts "==link config to #{dest}"
    end
  end

  desc 'edit', 'edit env config file'
  def edit
    cmds = <<~Desc
      vi #{local_env_file}
      echo #{local_env_file}
    Desc
    system cmds
  end

  no_commands do
    def local_env_file
      Pathname(ENV['LOCAL_ENV_FILE'] || app_config_for('env.local'))
    end

    def rails_env
      if in_dev?
        'development'
      elsif in_prod?
        'production'
      else
        env
      end
    end
  end
end

__END__

