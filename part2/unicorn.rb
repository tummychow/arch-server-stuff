# http://unicorn.bogomips.org/examples/unicorn.conf.rb
worker_processes 1

user 'peon'
working_directory '/home/peon/gollum'

# remember, these have to be readable/writable by the unicorn workers
listen '/home/peon/gollum/tmp/gollum.sock'
stdout_path '/home/peon/gollum/tmp/gollum.out.log'
stderr_path '/home/peon/gollum/tmp/gollum.err.log'
pid '/home/peon/gollum/tmp/gollum.pid'
