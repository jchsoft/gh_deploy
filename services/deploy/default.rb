module Services
  module Deploy
    class Default
      class << self
        def update_project
          Dir.chdir($config[:project][:path]) do
            output = `git pull`
          end
        end
      end
    end
  end
end
