module Dklet::DSL
  class << self
    def registry
      @_registry ||= {}
    end

    def dsl_methods
      @_dsl_methods ||= []
    end

    def dsl_method(mthd)
      dsl_methods << mthd
      define_method(mthd) do
        fetch_with_default(mthd)
      end
    end
  end

  def registry
    Dklet::DSL.registry
  end

  def add_dsl &blk
    Dklet::DSL.module_eval &blk
  end

  def dsl_methods
    Dklet::DSL.dsl_methods
  end
  
  def register(key, value)
    registry[key] = value
  end

  def fetch(key)
    val = registry[key]
    if val && val.respond_to?(:call)
      val = val.call
    end
    val
  end

  def fetch_with_default(key)
    provided = fetch(key)
    return provided if provided
    mthd = "default_#{key}"
    send(mthd) if respond_to?(mthd)
  end

  def register_docker_image(name)
    register :docker_image, name
  end

  # release is not relevant
  def default_docker_image
    "#{env}/#{appname}:#{image_tag}"
  end

  def default_image_tag
    "edge"
  end

  def default_image_labels
    app_labels = image_label_hash.map{|k, v| [k,v].join('=') }.join(' ')
    "maintainer=dailyops built_from=docklet #{app_labels}"
  end

  def image_label_hash
    {
      dklet_app: appname,
      dklet_env: env
    }
  end

  def release_label_hash
    image_label_hash.merge(dklet_release: app_release)
  end

  # maybe from external image
  def dkrun_cmd(labeled: true, opts: nil, named: false)
    cmd = "docker run"
    if labeled
      release_labels = release_label_hash.map do |k, v|
        "--label=#{k}=#{v}"
      end.join(' ')
      cmd += " #{release_labels}"
    end
    cmd += " --net #{netname}" if netname
    cmd += " --name #{container_name}" if named
    cmd += " #{opts}" if opts
    cmd
  end

  def dktmprun(opts: nil)
    cmd = dkrun_cmd(opts: "--rm -i #{opts}", labeled: false)
    "#{cmd} #{docker_image}"
  end

  def container_filters_for_release
    release_label_hash.map do |k, v|
      "--filter label=#{k}=#{v}"
    end.join(' ')
  end

  def containers_for_release
    `docker ps -aq #{container_filters_for_release}`.split("\n")
  end

  # Note: if img1:t1 = img2:t2 points to same image hashid, they will be selected as same
  def containers_for_image(img = docker_image)
    `docker ps -aq -f ancestor=#{img}`.split("\n")
  end

  def containers_in_net(net = netname)
    `docker ps -aq -f network=#{net}`.split("\n")
  end 

  def dklet_script
    Pathname($PROGRAM_NAME)
  end

  # 触发脚本所在(绝对)路径
  def script_path
    dklet_script.realdirpath.dirname
  end

  # use <parent_path_name>_<script_file_name> to ensure possible unique
  def script_name # not file name
    sname = fetch(:script_name)
    return sname if sname
    name = dklet_script.basename('.rb').to_s
    pname = script_path.basename.to_s
    "#{pname}_#{name}"
  end
  
  def set_file_for(name, str)
    register name, Dklet::Util.tmpfile_for(str)
  end

  def file_for(name)
    fetch(name)
  end

  def file_content_for(name)
    fpath = fetch(name)
    return unless fpath
    File.read(fpath)
  end

  # todo
  def dklet_config_for(name)
    p = Pathname("/dkconf/#{full_release_name}")
    p.mkpath unless p.directory?
    p.join(name)
  end

  def rendered_file_for(name, locals: {}, in_binding: binding)
    tmpl = file_content_for(name)
    return unless tmpl
    erb = ERB.new(tmpl, nil, '%<>')
    rendered = erb.result(in_binding)
    Dklet::Util.tmpfile_for(rendered)
  end

  # Dockerfile for image build
  def write_dockerfile(str, path: nil)
    set_file_for(:dockerfile, str)
    register_build_root(path) if path
  end

  def raw_dockerfile
    fetch(:dockerfile)
  end

  def dockerfile
    rendered_file_for(:dockerfile)
  end

  # specfile for k8s resources spec manifest
  def write_specfile(str)
    set_file_for(:specfile, str)
  end

  def raw_specfile
    fetch(:specfile)
  end

  ## rendered in current context
  def specfile
    rendered_file_for(:specfile)
  end

  def disable(key)
    (registry[:disable] ||= {})[key] = true
  end

  def disabled?(key)
    (registry[:disable] ||= {})[key]
  end

  # main dsl
  def task(name = :main, opts={}, &blk)
    type = opts.delete(:type) || :after
    hooks_name = "#{name}_#{type}_hooks".to_sym 
    (registry[hooks_name] ||= []) << blk
    task_opts(name).merge!(opts) unless opts.empty?
  end

  def before_task(name = :main, &blk)
    task(name, type: :before, &blk)
  end 

  def task_opts(name = :main)
    key = "opts_for_task_#{name}".to_sym
    registry[key] ||= {}
  end

  def let_cli_magic_start!
    DockletCLI.start
  end

  def custom_commands &blk
    DockletCLI.class_eval &blk
  end

  def add_note str
    (registry[:user_notes] ||= []) << str
  end

  def user_notes
    fetch(:user_notes)
  end

  # docker networking
  def register_net(name = :dailyops, build: false)
    register :netname, name
    ensure_docker_net(name) if build
  end

  def netname
    fetch(:netname)
  end

  def ensure_docker_net(name, driver: :bridge)
    unless netid = find_net(name)
      puts "create new network: #{name}"
      netid = `docker network create #{name} --label #{label_pair(:name, name)} --driver=#{driver}`
    end
    netid
  end

  # use label (not name) filter to avoid str part match
  def find_net(name)
    cmd = "docker network ls -q --filter label=#{label_pair(:name, name)}"
    netid = `#{cmd}`.chomp
    return netid unless netid.empty?
    nil
  end

  def label_key(key, prefix: true)
    prefix ? "docklet.#{key}" : key
  end

  # key=value pair
  def label_pair(key, val, prefix: true)
    [label_key(key, prefix: prefix), val].join('=')
  end

  ## project name for docker-compose
  def compose_name
    "#{fetch(:compose_name) || appname}_#{env}"
  end

  # -f, --file
  # -p, --project-name to altertive project name, eg. default net prefix
  def compose_cmd
    "docker-compose -f #{specfile} --project-name #{compose_name} --project-directory #{approot}"
  end 

  def register_approot path
    register_path(:approot, path)
  end

  def approot
    fetch(:approot) || build_root || script_path
  end

  def appname
    fetch(:appname) || script_name
  end

  # take into acccount: app, env, app_release
  def full_release_name
    [env, appname, app_release].compact.join('_')
  end

  # make path friendly 
  def release_path_name
    full_release_name.gsub(/_/, '-')
  end

  def register_app_tag(tag)
    app_tags << tag
  end

  def app_tags
    registry[:app_tags] ||= []
  end

  def smart_build_context_path
    # use explicitly specified, maybe nil
    return build_root if registry.has_key?(:build_root)
    # check build path dependent
    body = File.read(dockerfile)
    need_path = body =~ /^\s*(ADD|COPY)\s/i
    script_path if need_path
  end

  def register_build_root path
    register_path(:build_root, path)
  end

  def build_root
    fetch(:build_root)
  end

  def register_build_net net
    register(:build_net, net)
  end

  def build_net
    fetch(:build_net)
  end

  def register_path key, path
    path = Pathname(path) unless path.is_a?(Pathname)
    register key, path
  end

  def register_ops(cid)
    register :ops_container, cid
  end

  def default_ops_container
    containers_for_release.first # || container_name
  end

  def default_container_name
    full_release_name
  end

  def container_missing
    puts "Not found container for image: #{docker_image}"
  end

  def register_default_env(str)
    register :default_env, str
  end

  def env
    ENV['APP_ENV'] || fetch(:default_env) || 'dev'
  end

  # 标识一次运行发布的用途, 如redis for hirails-only
  def app_release
    ENV['APP_RELEASE'] || 'default'
  end

  def volumes_root
    vols_root = "#{ENV['HOME']}/DockerVolumes"
    root = fetch(:volumes_root) || if File.directory?(vols_root)
        # friendly to File sharing on Docker for Mac
        vols_root
      else
        '~/docker-volumes'
      end
    proot = Pathname(root)
    proot.mkpath unless proot.directory?
    proot
  end

  def default_app_volumes
    volumes_root.join(release_path_name)
  end

  ## top proxy domain part
  def proxy_domain
    ENV['LOCAL_DKLET_DOMAIN'] || 'lh'
  end

  def domain_for(*doms)
    doms.map{|d| "#{d}.#{proxy_domain}" }.join(',')
  end

  # ref dklet/mac/
  def host_domain_in_container
    ENV['HOST_DOMAIN_IN_CONTAINER'] || 'host.dokcer.internal'
  end
end

%i(
  docker_image
  image_tag
  image_labels
  container_name
  ops_container
  app_volumes
).each{|m| Dklet::DSL.dsl_method(m) }
