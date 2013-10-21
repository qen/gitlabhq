class GitlabShellWorker
  include Sidekiq::Worker
  include Gitlab::ShellAdapter

  sidekiq_options queue: :gitlab_shell

  def perform(action, *arg)
    logger.info "#{action} | #{arg.inspect}"
    gitlab_shell.send(action, *arg)
  end
end
