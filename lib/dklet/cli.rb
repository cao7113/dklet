require "thor"
class DockletCLI < Thor
  #include Thor::Actions
  default_command :main

  class_option :debug, type: :boolean, default: false, banner: 'in debug mode, more log'
  class_option :dry, type: :boolean, default: false, banner: 'dry run'
  class_option :quiet, type: :boolean, default: false, banner: 'keep quiet'
  class_option :force, type: :boolean, default: false, banner: 'force do'
  class_option :env, banner: 'app env', aliases: ['-e']
  class_option :release, banner: 'what app release for', aliases: ['-r']

  desc 'version', 'show dklet version'
  def version
    puts Dklet.version
  end
  map '-v' => "version"

  desc 'main', 'main user entry'
  option :preclean, type: :boolean, default: true, banner: 'clean before do anything'
  option :build, type: :boolean, default: true, banner: 'build image'
  def main
    invoke_clean if options[:preclean] && task_opts(:main)[:preclean] != false

    invoke_hooks_for(:main, type: :before)
    invoke :build, [], {} if options[:build] && task_opts(:main)[:build] != false
    invoke_hooks_for(:main)
  end

  desc 'console', 'get ruby console'
  def console
    pp registry
    byebug 
    puts "=ok"
  end

  desc 'log [CONTAINER]', 'logs in container'
  def log(cid = ops_container)
    unless cid
      container_missing
      return
    end
    system <<~Desc
      docker logs -t -f --details #{cid}
    Desc
  end

  desc 'runsh [CONTAINER]', 'run into container'
  option :cmd, banner: 'run command in container'
  option :opts, banner: 'docker run options'
  option :tmp, type: :boolean, default: false, banner: 'allow run tmp container'
  def runsh(cid = ops_container)
    tmprun = options[:tmp]
    if tmprun
      dkcmd = "docker run -t -d" 
      dkcmd += " --network #{netname}" if netname
      dkcmd += " #{options[:opts]}" if options[:opts]
      cid = `#{dkcmd} #{docker_image} sleep 3d`.chomp
      puts "==run tmp container: #{cid}" unless options[:quiet]
    end

    abort "No container found!" unless cid

    cmd = options[:cmd] || 'sh'
    puts "run : #{cmd}" unless options[:quiet]

    if cmd == 'sh' # simple case
      cmds = <<~Desc
        docker exec -it #{options[:opts]} #{cid} #{cmd}
      Desc
    else
      tfile = Dklet::Util.tmpfile_for cmd
      dst_file = "/tmp/dklet-#{File.basename(tfile)}-#{rand(10000)}"
      # todo user permissions for pg
      cmds = <<~Desc
        docker cp --archive #{tfile} #{cid}:#{dst_file}
        docker exec -it #{options[:opts]} #{cid} sh -c 'sh #{dst_file} && rm -f #{dst_file}'
      Desc
    end
    puts cmds unless options[:quiet]
    system cmds unless options[:dry]

    if tmprun
      system <<~Desc
        docker rm -f #{cid}
      Desc
    end
  end
  map "sh" => :runsh

  desc 'daemon', 'docker run in daemon'
  option :opts, banner: 'run extra options'
  def daemon
    invoke :build, [], {}
    system "docker run -d #{options[:opts]} #{docker_image}" unless options[:dry]
  end

  desc 'build', 'build image'
  option :opts, banner: 'build extra options like --no-cache'
  def build
    return unless dockerfile

    unless options[:dry]
      invoke_hooks_for(:build, type: :before)
    end

    cmd = "docker build --tag #{docker_image}"
    net = build_net
    cmd += " --network #{net}" if net
    cmd += " #{options[:opts]}" if options[:opts]

    bpath = smart_build_context_path
    cmd = if bpath
      "#{cmd} --file #{dockerfile} #{bpath}"
    else # nil stand for do not need build context
      "cat #{dockerfile} | #{cmd} -"
    end
    puts "build command:\n  #{cmd}" if options[:debug]

    system cmd unless options[:dry]
  end

  desc 'note', 'display user notes'
  def note
    puts user_notes.join("\n")
  end

  desc 'clean', 'clean container artifacts'
  # keep cache reused
  option :image, type: :boolean, default: false, banner: 'clean user-derived images'
  def clean
    invoke_hooks_for(:clean, type: :before)

    unless specfile # do not clean container if compose-file exists
      cids = containers_for_release
      unless cids.empty?
        str_ids = cids.join(' ')
        system <<~Desc
          echo ==clean containers: #{str_ids}
          docker rm --force #{str_ids}
        Desc
      end
    end

    invoke_hooks_for(:clean)

    if options[:image] && dockerfile
      system <<~Desc
        echo ==clean image: #{docker_image}
        docker rmi --force #{docker_image} 2>/dev/null
      Desc
    end
  end

  desc 'spec', 'display specs'
  option :spec, type: :boolean, default: true, banner: 'show rendered specfile'
  option :dockerfile, type: :boolean, default: true, banner: 'show Dockerfile'
  def spec
    if options[:spec] && specfile
      puts File.read(specfile)
      puts "# rendered at #{specfile}" if options[:debug]
    end
    if options[:dockerfile] && dockerfile
      puts File.read(dockerfile)
      puts "# Dockerfile at #{dockerfile} " if options[:debug]
    end
  end

  desc 'image_name', 'display image name'
  def image_name
    puts docker_image
  end

  desc 'image', 'list related image'
  def image
    system "docker images #{docker_image}"
  end 

  desc 'ps', 'ps related containers'
  option :imaged, type: :boolean, default: false, banner: 'same image digest'
  def ps
    cmd = if options[:imaged]
        "docker ps -f ancestor=#{docker_image} -a"
      else
        "docker ps #{container_filters_for_release} -a"
      end
    puts cmd if options[:debug]
    system cmd unless options[:dry]
  end

  desc 'netup [NETNAME]', 'make networking'
  def netup(net = netname)
    return unless net
    ensure_docker_net(net)
    puts "network #{net} working"
  end

  desc 'netdown [NETNAME]', 'clean networking'
  def netdown(net = netname)
    puts "cleaning net: #{net}" if options[:debug]
    return unless net
    return unless find_net(net)

    cids = containers_in_net(net)
    binded = !cids.empty?
    if binded 
      if options[:force] || yes?("#{cids.size} containers linked, FORCELY remove(y|n)?")
        system "docker rm -f #{cids.join(' ')}"
        binded = false
      end
    end
    if binded
      puts "#{net} has binded resources, skipped"
    else
      system "docker network rm #{net}"
      puts "network #{net} cleaned"
    end
  end

  desc 'netps [NETNAME]', 'ps in a network' 
  def netps(net = netname)
    return unless net
    system <<~Desc
      docker ps -f network=#{net} -a
    Desc
  end

  desc 'netls', 'list networks' 
  def netls()
    system <<~Desc
      docker network ls
    Desc
  end

  desc 'comprun', 'compose run'
  def comprun(*args)
    cmd = <<~Desc
      #{compose_cmd} #{args.join(' ')}
    Desc
    puts cmd if options[:debug]
    system cmd unless options[:dry]
  end

  desc 'vols', 'ls volumes'
  def vols
    system <<~Desc
      ls -l #{volumes_root}/
    Desc
  end

  desc 'clear_app_volumes', 'clear app volumes'
  def clear_app_volumes
    if app_volumes.directory?
      if options[:force] || yes?("Remove app volumes dir data?")
        app_volumes.rmtree
      end
    end
  end

  desc 'inspect_info', 'inspect info'
  option :image, type: :boolean, default: false, aliases: ['-i'], banner: 'inspect image'
  option :container, type: :boolean, default: false, aliases: ['-c'], banner: 'inspect container'
  def inspect_info
    cmd = nil
    if options[:image]
      cmd = "docker inspect #{docker_image}"
    elsif options[:container]
      cid = containers_for_release.first || container_name || ops_container
      cmd = "docker inspect #{cid}"
    else
      h = {
        script: dklet_script,
        script_path: script_path,
        script_name: script_name,
        appname: appname,
        env: env,
        release: app_release,
        full_release_name: full_release_name,
        container_name: container_name,
        image: docker_image,
        approot: approot,
        build_root: build_root,
        build_net: build_net,
        release_labels: release_label_hash,
        network: netname,
        voluemes_root: volumes_root,
        app_volumes: app_volumes,
        domain: proxy_domain,
        dsl_methods: dsl_methods,
        registry: registry
      }
      pp h
    end
    system cmd if cmd
  end
  map 'inspect' => 'inspect_info'
  map 'info' => 'inspect_info'

  desc 'mock1', ''
  def mock1(time)
    puts "invoked at #{time}"
  end

  desc 'mock2', ''
  def mock2
    invoke :mock1, [Time.now]
    puts 'first invoked'
    invoke :mock1, [Time.now]
    puts 'sencond invoked'

    invoke2 :mock1, [Time.now], {}
    puts 'third invoked'
    invoke2 :mock1, [Time.now], {}
    puts '4th invoked'
  end

  no_commands do
    include Dklet::DSL

    def invoke_clean
      invoke :clean, [], {}
    end

    def invoke_hooks_for(name = :main, type: :after)
      hooks_name = "#{name}_#{type}_hooks".to_sym
      hooks = fetch(hooks_name)
      if hooks && !hooks.empty?
        hooks.each do |hook|
          # eval by receiver dierectly
          instance_eval &hook if hook.respond_to?(:call)
        end
      end
    end

    # https://github.com/erikhuda/thor/issues/73
    def invoke2(task, args, options)
      (klass, task) = Thor::Util.find_class_and_command_by_namespace(task)
      klass.new.invoke(task, args, options)
    end

    def container_run(cmds, opts = nil)
      cmds = cmds.join("\n") if cmds.is_a?(Array)
      opts = (opts||{}).merge(cmd: cmds).merge(options.slice('quiet', 'dry'))
      invoke :runsh, [], opts
    end

    # encapsulate run commands behaviors in system
    def system_run(cmds, opts={})
      unless options[:quiet]
        puts cmds
      end
      unless options[:dry]
        system cmds
      end
    end
  end # of no_commands
end
