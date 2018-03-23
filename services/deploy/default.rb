# frozen_string_literal: true

module Services
  module Deploy
    class Default
      # @param [Symbol] :project
      def self.update(project)
        Dir.chdir($config[:projects][project][:path]) do
          $logger.debug Dir.getwd
          $config[:projects][project][:commands].each do |command|
            if command.key?(:run)
              $logger.debug `#{command[:run]}`
              return false, "#{command[:run]} failed" if $CHILD_STATUS.exitstatus
            end
          end
        end
        [true, 'all is OK']
      end
    end
  end
end
