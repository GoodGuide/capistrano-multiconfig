Capistrano::Configuration.instance(true).load do
  # configurations root directory
  config_root = File.expand_path(fetch(:config_root, "config/deploy"))

  # list of configurations files
  config_files = Dir["#{config_root}/**/*.rb"]

  # remove configuration file if it's part of another configuration
  config_files.reject! do |config_file|
    config_dir = config_file.gsub(/\.rb$/, '/')
    config_files.any? { |file| file[0, config_dir.size] == config_dir }
  end

  # build configuration names list
  alias_names = []
  config_names = []

  config_files.each do |config_file|
    task_name = config_file.sub("#{config_root}/", '').sub(/\.rb$/, '').gsub('/', ':')

    if File.symlink?(config_file)
      target = File.realpath(config_file)
      # p symlink: true, config_file: config_file, target: target
      next unless File.dirname(target) == File.dirname(config_file)
      target_task = target.sub("#{config_root}/", '').sub(/\.rb$/, '').gsub('/', ':')
      alias_names << [task_name, target_task]
    else
      config_names << task_name
    end
  end
  # p alias_names

  # ensure that configuration segments don't override any method, task or namespace
  config_names.each do |config_name|
    config_name.split(':').each do |segment|
      if all_methods.any? { |m| m == segment }
        raise ArgumentError,
          "Config task #{config_name} name overrides #{segment.inspect} (method|task|namespace)"
      end
    end
  end

  def create_task_in_namespaces(full_task_name, description="Load #{full_task_name} configuration",  &task_body)
    *namespace_names, task_name = full_task_name.split(':')

    # create configuration task block.
    # NOTE: Capistrano 'namespace' DSL invokes instance_eval that
    # that pass evaluable object as argument to block.
    block = lambda do |parent|
      p desc: description
      desc description
      p task: task_name
      parent.task(task_name, &task_body)
    end

    # wrap task block into namespace blocks
    block = namespace_names.reverse.inject(block) do |child, name|
      lambda do |parent|
        p namespace: name
        parent.namespace(name, &child)
      end
    end

    # create namespaced configuration task
    block.call(top)
  end

  alias_names.each do |(alias_name, target_task)|
    create_task_in_namespaces(alias_name, "Load #{target_task} configuration") do
      warn "#{alias_name} is an alias. Loading task #{target_task}"
    end

    after alias_name, target_task
  end

  # create configuration task for each configuration name
  config_names.each do |config_name|
    all_tasks_to_run = config_name.split(':').inject([]){ |a,e| a + [[a.last, e].compact.join(':')] }

    create_task_in_namespaces(config_name) do
      # set configuration name as :config_name variable
      top.set(:config_name, config_name)

      # recursively load configurations
      all_tasks_to_run.each do |task_name|
        path = [config_root, *task_name.split(':')].join('/') + '.rb'
        p config_name: config_name, load_path: path
        top.load(:file => path) if File.exists?(path)
      end
    end
  end

  # set configuration names list
  set(:config_names, config_names + alias_names.map(&:first))
end
