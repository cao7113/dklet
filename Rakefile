require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

desc 'test dklet gem'
task :test do
  app_path = 'tmp/hidklet'
  result = system <<~Desc
    mkdir -p #{File.dirname(app_path)}
    rm -f #{app_path}
    mkdklet #{app_path}
    #{app_path} help
    #{app_path} # main task
    #{app_path} clean --image
  Desc

  if result
    puts 'everything ok' 
  else
    puts 'something wrong'
  end
end
