APP_PATH = File.expand_path('../../../../', File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__ )
APP_ROOT  = APP_PATH + '/current'

# yum install libevent libevent-devel
God.watch do |w|
  # rvm wrapper ruby-1.8.7-p334@smart_ph smart_ bundle
  w.name      = "smartph_gitlab_sidekiq"
  w.start     = "smartph_gitlab_bundle exec sidekiq -q post_receive,mailer,system_hook,project_web_hook,gitlab_shell,common,default -e production -L #{APP_PATH}/shared/log/sidekiq.log"
  #w.pid_file  = File.join(APP_PATH, "/shared/pids/sidekiq_production.pid")
  w.start_grace   = 30.seconds
  w.restart_grace = 30.seconds
  w.interval      = 30.seconds
  w.behavior(:clean_pid_file)

  w.env = { 'RAILS_ENV'       => "production",
            'RAILS_GROUPS'    => "production",
            'RAILS_ROOT'      => APP_ROOT,
            'BUNDLE_GEMFILE'  => "#{APP_ROOT}/Gemfile" }

  w.dir = APP_ROOT
  w.log = "#{APP_ROOT}/log/sidekiq_production.log"
#
#  w.transition(:up, :restart) do |on|
#    on.condition(:memory_usage) do |c|
#      c.interval  = 10.minutes
#      c.above     = (1024 * 3).megabytes # 4gb
#      c.times     = 2
#    end
#  end


  # determine the state on startup
  w.transition(:init, {true => :up, false => :start}) do |on|
    on.condition(:process_running) do |c|
      c.running = true
    end
  end

  # determine when process has finished starting
  w.transition([:start, :restart], :up) do |on|
    on.condition(:process_running) do |c|
      c.running = true
      c.interval = 5.seconds
    end

    # failsafe
    on.condition(:tries) do |c|
      c.times = 5
      c.transition = :start
      c.interval = 5.seconds
    end
  end

  # start if process is not running
  w.transition(:up, :start) do |on|
    on.condition(:process_running) do |c|
      c.running = false
    end
  end


#  # Notifications
#  # --------------------------------------
#  w.transition(:up, :start) do |on|
#    on.condition(:process_exits) do |p|
#      p.notify = 'ect'
#    end
#  end

  w.keepalive
end
