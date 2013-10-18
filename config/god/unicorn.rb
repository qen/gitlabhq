APP_PATH = File.expand_path('../../../../', File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__ )
APP_ROOT  = APP_PATH + '/current'

module God
  module Conditions
    class RestartFileTouched < PollCondition
      attr_accessor :restart_file
      def initialize
        super
      end

      def process_start_time
        #@started_at ||= Time.parse('-1 minute')
        pid = self.watch.pid || $$
        Time.parse(`ps -o lstart -p #{pid} --no-heading`)
        #@started_at
      end

      def restart_file_modification_time
        File.mtime(self.restart_file)
      end

      def valid?
        valid = true
        valid &= complain("Attribute 'restart_file' must be specified", self) if self.restart_file.nil?
        valid
      end

      def test
        process_start_time < restart_file_modification_time
      end
    end
  end
end

God.watch do |w|
  # rvm wrapper ruby-1.8.7-p334@sandi sandi187 bundle
  w.name      = "smartph_gitlab"
  w.start     = "smartph_gitlab_bundle exec unicorn -c #{APP_ROOT}/config/unicorn/production.rb -D"
  w.pid_file  = File.join(APP_PATH, "/shared/pids/unicorn_production.pid")

  w.behavior(:clean_pid_file)

  w.env = { 'RAILS_ENV'       => "production",
            'RAILS_GROUPS'    => "production",
            'RAILS_ROOT'      => APP_ROOT,
            'BUNDLE_GEMFILE'  => "#{APP_ROOT}/Gemfile" }

  w.dir = APP_ROOT
  w.log = "#{APP_ROOT}/log/unicorn_production.log"

  w.transition(:up, :restart) do |on|
    on.condition(:memory_usage) do |c|
      c.interval  = 10.minutes
      c.above     = (1024 * 3).megabytes # 4gb
      c.times     = 2
    end
  end

  w.keepalive
end
