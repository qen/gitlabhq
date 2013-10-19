set :application, "SmartPH Gitlab"
set :repository,  "git@github.com:qen/gitlabhq.git"
set :branch,      "smartph"
set :scm,         :git

set :user,        "deploy"
set :use_sudo,    false

set :deploy_to,   "/var/www/smartph/gitlab/production"
set :shared_path, "#{deploy_to}/shared"


role :web, "kagebunshin"
role :app, "kagebunshin" # this can be the same as the web server
role :db,  "amateratsu", :primary => true # this can be the same as the web server

set :ruby_version,  "ruby-2.0.0-p247"
set :rvm_gemset,    "smartph_gitlab"
#set :rvm_bin,       'rvm'
#set :rvm_bin,       '/usr/local/rvm/bin/rvm'
#set :rvm_path,      '~/.rvm'
#set :rvm_path,      '/usr/local/rvm'

default_run_options[:pty]   = true
default_run_options[:shell] = false # disable sh wrapping
#set :default_shell, "bash -l"

################################################################################
# CONFIGURATIONS
################################################################################

set :normal_symlinks, %w(
  config/database.yml
  config/gitlab.yml
  config/resque.yml
  tmp
  log
  .rvmrc
  .bundle
  vendor/bundle
)

# need to symlink tmp/restart.txt file to shared folder
# so that jobdaemon would restart too
set :weird_symlinks, {
  'assets'  => 'public/assets',
  'uploads' => 'public/uploads',
}

set :shared_folders, %w(
  log
  tmp/pids
  tmp/sockets
  config
  scripts
  assets
  uploads
  .bundle
  vendor/bundle
)

set :shared_files, %w(
  config/database.yml
  config/gitlab.yml
  config/resque.yml
)

set :rsync_exclude_lists, %w(
  .git/*
  tmp/*
  log/*
  .rails
  config/*.yml
  config/*.example
  .gitignore
  .rspec
  .sass-cache/*
  .bundle/*
  nbproject/*
)

################################################################################
# deployment to different server
################################################################################


################################################################################
# deploy HOOKS here
################################################################################

namespace :make do
  #desc "Make all the damn symlinks"
  task :symlinks, :roles => :app, :except => { :no_release => true } do
    commands = normal_symlinks.map do |path|
      "rm -rf #{release_path}/#{path} && \
       ln -s #{shared_path}/#{path} #{release_path}/#{path}"
    end

    commands += weird_symlinks.map do |from, to|
      "rm -rf #{release_path}/#{to} && \
       ln -s #{shared_path}/#{from} #{release_path}/#{to}"
    end

    # needed for some of the symlinks
    #run "mkdir -p #{current_path}/tmp"

    run <<-CMD
      export rvm_trust_rvmrcs_flag=1; cd #{release_path} && #{commands.join(" && ")}
    CMD
  end

end

after "deploy",             "deploy:cleanup"
after "deploy:update_code", "make:symlinks"


def setup_git_user
=begin

=end
end

#-------------------------------------------------------------------------------
# initializes shared folder directory and files
#-------------------------------------------------------------------------------
after "deploy:setup" do
  commands = []

  shared_folders.map do |path|
    commands << "mkdir -p #{shared_path}/#{path}"
  end

  shared_files.map do |file|
    commands << "touch #{shared_path}/#{file}"
  end

  rvm = (rvm_bin rescue nil) || 'rvm'
  begin
    commands << "[[ -s #{rvm_path}/scripts/rvm ]] && . #{rvm_path}/scripts/rvm;" if not rvm_path.blank?
  rescue
  end
  #commands << "[ -s #{shared_path}/.rvmrc ] && #{rvm} rvmrc trust #{shared_path}"
  #commands << "[ -s #{shared_path}/.rvmrc ] && #{rvm} rvmrc trust #{deploy_to}"
  commands << "#{rvm} install #{ruby_version}"
  commands << "rm .rvmrc"
  commands << "#{rvm} use #{ruby_version}@#{rvm_gemset} --rvmrc --create"
  commands << "cd #{deploy_to} "
  commands << "ln -sf #{shared_path}/.rvmrc #{deploy_to}/.rvmrc"
  #commands << "[ -s #{shared_path}/.rvmrc ] && #{rvm} rvmrc trust #{deploy_to}"
  #commands << "[ -s #{shared_path}/.rvmrc ] && #{rvm} rvmrc trust #{shared_path}"
  commands << "#{rvm} wrapper #{ruby_version}@#{rvm_gemset} #{rvm_gemset} bundle"
  commands << "#{rvm} wrapper #{ruby_version}@#{rvm_gemset} #{rvm_gemset} rake"

  run <<-CMD
    export rvm_trust_rvmrcs_flag=1; cd #{shared_path}; touch .rvmrc; #{commands.join(" && ")}
  CMD

  # CREATES RAKE SCRIPT
  run "echo -e '#{rake_script}'  > #{shared_path}/scripts/rake && chmod +x #{shared_path}/scripts/rake"

  # CREATES BUNDLE SCRIPT
  run "echo -e '#{bundle_script}'  > #{shared_path}/scripts/bundle && chmod +x #{shared_path}/scripts/bundle"

  upload "Gemfile", "#{shared_path}", :via => :scp
  #run "cd #{shared_path} && scripts/bundle"
  run "cd #{shared_path} && #{rvm_gemset}_bundle install  --deployment --without development test mysql puma aws"

end


def god_init_script
(<<EOL
#!/bin/bash
#
# God
#
# chkconfig: - 85 15
# description: start, stop, restart God (bet you feel powerful)
#

god_usr="#{user}"
god_cmd=/usr/local/rvm/bin/#{rvm_gemset + '_god'}
god_cnf=/etc/godr/*.rb

# http://stackoverflow.com/questions/394984/best-practice-to-run-linux-service-as-a-different-user
# Source function library.
. /etc/rc.d/init.d/functions

RETVAL=0

case "$1" in
    start)
      daemon --user=$god_usr $god_cmd
      for f in $god_cnf
      do
        echo "loading $f"
        daemon --user=$god_usr $god_cmd load $f
      done

      RETVAL=$?
      echo "Starting god $god_cnf"
      ;;
    stop)
      daemon --user=$god_usr $god_cmd terminate
      RETVAL=$?
      echo "Stopping god $god_cnf"
      ;;
    restart)
      daemon --user=$god_usr $god_cmd terminate
      for f in $god_cnf
      do
        echo "loading $f"
        daemon --user=$god_usr $god_cmd
      done
      RETVAL=$?
      echo "Restarting god $god_cnf"
      ;;
    status)
      daemon --user=$god_usr $god_cmd status
      RETVAL=$?
      echo
      ;;
    *)
      echo "Usage: god {start|stop|restart|status}"
      exit 1
  ;;
esac

exit $RETVAL
EOL
).gsub("\n", "\\n")
end

def rake_script
  (<<EOL
#!/usr/bin/env bash
source /home/#{user}/.rvm/scripts/rvm
. #{shared_path}/.rvmrc
echo Started: `date`
echo \"Environment: $RAILS_ENV @ $(rvm-prompt i v p g)\"
export BUNDLE_GEMFILE='#{current_path}/Gemfile'
time bundle exec rake --trace -f #{current_path}/Rakefile $*
echo Ended: `date`
EOL
  ).gsub("\n", "\\n")
end

def bundle_script
  (<<EOL
#!/usr/bin/env bash
source /home/#{user}/.rvm/scripts/rvm
. #{shared_path}/.rvmrc
echo \"Environment: $RAILS_ENV @ $(rvm-prompt i v p g)\"
export BUNDLE_GEMFILE='#{current_path}/Gemfile'
bundle $*
EOL
  ).gsub("\n", "\\n")
end


# if you want to clean up old releases on each deploy uncomment this:
# after "deploy:restart", "deploy:cleanup"

# if you're still using the script/reaper helper you will need
# these http://github.com/rails/irs_process_scripts

# If you are using Passenger mod_rails uncomment this:
# namespace :deploy do
#   task :start do ; end
#   task :stop do ; end
#   task :restart, :roles => :app, :except => { :no_release => true } do
#     run "#{try_sudo} touch #{File.join(current_path,'tmp','restart.txt')}"
#   end
# end