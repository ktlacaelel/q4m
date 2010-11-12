require 'rubygems'
require 'mysql'
require 'logger'

module Q4m

  module Queue

    class Job

      # Job initializer.
      #
      # ::mysql:: a Mysql instance
      # ::log:: a Logger instance
      #
      def initialize mysql, log
        @mysql, @log = mysql, log
        look_for_jobs!
      end

      # Job runner.
      #
      # - Locks the queue.
      # - Executes the latest job.
      # - Restores the queue so other worker can execute a process.
      #
      def run terminate = false
        return unless @has_jobs
        queue_wait
        @log.info("Executing: #{latest_job.inspect}")
        execute latest_job
        queue_end
        shutdown if terminate
        nil
      end

      # Shuts down the worker
      #
      def shutdown
        @mysql.close
        @log.close
        nil
      end

      private

      # Job availability checker.
      #
      # Check if queue has any jobs.
      #
      def look_for_jobs!
        @has_jobs = true
        @mysql.query("select count(*) from #{table_name}").each do |queue|
          if queue == ['0']
            @has_jobs = false
          end
        end
      end

      protected

      # Latest job fetcher.
      #
      # Retrives one mysql record representing a queue-job.
      #
      def latest_job
        @mysql.query("select * from #{table_name}").each do |job|
          return job
        end
      end

      # Job locker.
      #
      # Tells the queue to operate in locked mode. By pulling out the
      # latest job, and locking the whole queue-stack.
      #
      # When anyone tries to pull jobs from the queue the very same
      # job will be returned until the queue status is changed with
      # one of the following options:
      #
      #  - terminated (queue_end)
      #  - aborted    (queue_abort)
      #
      def queue_wait
        @mysql.query "select queue_wait('#{table_name}')"
      end

      # Job unlocker.
      #
      # Tells the q4m engine that this job is terminated. Then mysql
      # will internally delete the job from the queue/database.
      #
      # Once this is done all jobs will be available until someone
      # locks the queue again.
      #
      def queue_end
        @mysql.query 'select queue_end()'
      end

      # Job rollback.
      #
      # This method should be executed after the queue has been locked
      # only!
      #
      # If executed, it'll tell the engine that the job failed to be
      # terminated and should stay in the queue for later processing.
      #
      # When this happens the job is restored to the queue for later
      # processing. But you should still unlock the queue so it can
      # start serving other workers
      #
      def queue_abort
        @log.error 'Aborted!'
        @mysql.query 'select queue_abort()'
      end

      # Job table name.
      #
      # This method is here so child classes can define the tablename
      # that they pull out jobs from by overriding.
      #
      def table_name
        s = self.class.name.split(/::/).last
        s.gsub(/([A-Z])/, '_\1').gsub(/^_|::/, '').downcase + 's'
      end

      # Job execution.
      #
      # Child classes should define how exactly the job is to be
      # executed!
      #
      def execute job
        raise 'Must implement in a child class!'
      end

    end

  end

end
